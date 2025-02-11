##########################################################################
# Get the yearly time series data for the OPF. 
##########################################################################

# struct defined to make it less annoying to unpack the data
struct yearly_ISPhvdc_time_series
    year
    total_demand_series
    average_demand_per_state
    pv_series
    wind_series
    pv_rez
    wind_rez
end

function get_ISPhvdc_time_series(
    scenario, year, data_dir
)

    # prepare time series for hourly calculations
    # Get installed generator info, e.g. installed generation type and capacity from the ISP data
    generator_info = _ISP.get_generator_information(; data_dir=data_dir)
    # Get RES time series, e.g. traces from the ISP data
    pv, wind = _ISP.get_res_timeseries(year; data_dir=data_dir)
    # Aggregate timeseries to obtain one profile for existing RES
    pv_series, count_pv = _ISP.aggregate_res_timeseries(pv, generator_info, "Solar")
    wind_series, count_wind = _ISP.aggregate_res_timeseries(wind, generator_info, "Wind")
    # Aggregate timeseries to obtain one profile for renewable energy zones (REZ)
    pv_rez = _ISP.make_rez_time_series(pv)
    wind_rez = _ISP.make_rez_time_series(wind)
    # Get demand traces for selected year, for each state
    total_demand_series = _ISP.get_demand_data(scenario, year; data_dir=data_dir)
    average_demand_per_state = Dict{String,Any}([state => mean(timeseries) for (state, timeseries) in total_demand_series])

    return yearly_ISPhvdc_time_series(
        year,
        total_demand_series,
        average_demand_per_state,
        pv_series,
        wind_series,
        pv_rez,
        wind_rez
    )
end

##########################################################################
# Functions for editing the network data before it is used for the OPF.
##########################################################################

# this is a modified function from the PowerModelsACDCSecurityConstrained.jl package
# splits large coal powerplants into smaller units
function split_large_coal_powerplants_to_units!(data)
    split_generators = []
    for (i, gen) in data["gen"]
        if gen["fuel"] == "Coal" && gen["pmax"] > 5.0
            push!(split_generators, i)
        end
    end
    index_new = length(data["gen"])+1:length(data["gen"])+length(split_generators)
    new_gen_pairs = []
    for i in eachindex(split_generators)
        push!(new_gen_pairs, (index_new[i], split_generators[i]))
    end
    for (i, j) in new_gen_pairs
        data["gen"]["$i"] = deepcopy(data["gen"]["$j"])
        data["gen"]["$i"]["Ramp_Up_Rate(MW/h)"] = data["gen"]["$i"]["Ramp_Up_Rate(MW/h)"] / 2
        data["gen"]["$i"]["mbase"] = data["gen"]["$i"]["mbase"] / 2
        data["gen"]["$i"]["qmax"] = data["gen"]["$i"]["qmax"] / 2
        data["gen"]["$i"]["Ramp_Down_Rate(MW/h)"] = data["gen"]["$i"]["Ramp_Down_Rate(MW/h)"] / 2
        data["gen"]["$i"]["qmin"] = data["gen"]["$i"]["qmin"] / 2
        data["gen"]["$i"]["pmin"] = data["gen"]["$i"]["pmin"] / 2
        data["gen"]["$i"]["qg"] = data["gen"]["$i"]["qg"] / 2
        data["gen"]["$i"]["source_id"] = Any["gen", i]
        data["gen"]["$i"]["index"] = i
        data["gen"]["$i"]["pg"] = data["gen"]["$i"]["pg"] / 2
        data["gen"]["$i"]["pmax"] = data["gen"]["$i"]["pmax"] / 2

        data["gen"]["$j"]["Ramp_Up_Rate(MW/h)"] = data["gen"]["$j"]["Ramp_Up_Rate(MW/h)"] / 2
        data["gen"]["$j"]["mbase"] = data["gen"]["$j"]["mbase"] / 2
        data["gen"]["$j"]["qmax"] = data["gen"]["$j"]["qmax"] / 2
        data["gen"]["$j"]["Ramp_Down_Rate(MW/h)"] = data["gen"]["$j"]["Ramp_Down_Rate(MW/h)"] / 2
        data["gen"]["$j"]["qmin"] = data["gen"]["$j"]["qmin"] / 2
        data["gen"]["$j"]["pmin"] = data["gen"]["$j"]["pmin"] / 2
        data["gen"]["$j"]["qg"] = data["gen"]["$j"]["qg"] / 2
        data["gen"]["$j"]["pg"] = data["gen"]["$j"]["pg"] / 2
        data["gen"]["$j"]["pmax"] = data["gen"]["$j"]["pmax"] / 2
    end
    return data
end

# this is a modified function from the PowerModelsACDCSecurityConstrained.jl package
# changed iterators in loops because ISPhvdc data has missing keys (deleted gens, branches, buses, etc)
function fix_opf_data_issues!(data;
    split_large_coal_gens=true,
    tm_min=0.9, tm_max=1.1, ta_min=-15, ta_max=15,
)

    # Defining generator areas sets: data["area_gens"]

    set1 = Set{Int64}()
    set2 = Set{Int64}()
    set3 = Set{Int64}()
    set4 = Set{Int64}()
    set5 = Set{Int64}()

    for i in parse.(Int64, keys(data["gen"]))
        gen_bus = data["gen"]["$i"]["gen_bus"]
        if data["bus"]["$gen_bus"]["area"] == 1
            push!(set1, data["gen"]["$i"]["index"])
        elseif data["bus"]["$gen_bus"]["area"] == 2
            push!(set2, data["gen"]["$i"]["index"])
        elseif data["bus"]["$gen_bus"]["area"] == 3
            push!(set3, data["gen"]["$i"]["index"])
        elseif data["bus"]["$gen_bus"]["area"] == 4
            push!(set4, data["gen"]["$i"]["index"])
        elseif data["bus"]["$gen_bus"]["area"] == 5
            push!(set5, data["gen"]["$i"]["index"])
        end
    end

    data["area_gens"] = Dict{Int64,Set{Int64}}()
    data["area_gens"][1] = set1
    data["area_gens"][2] = set2
    data["area_gens"][3] = set3
    data["area_gens"][4] = set4
    data["area_gens"][5] = set5

    # Defining generator participation factors: gen["alpha"]
    gen_total1 = sum(data["gen"]["$i"]["pmax"] for i in collect(set1))
    gen_total2 = sum(data["gen"]["$i"]["pmax"] for i in collect(set2))
    gen_total3 = sum(data["gen"]["$i"]["pmax"] for i in collect(set3))
    gen_total4 = sum(data["gen"]["$i"]["pmax"] for i in collect(set4))
    gen_total5 = sum(data["gen"]["$i"]["pmax"] for i in collect(set5))

    for i in collect(set1)
        if data["gen"]["$i"]["type"] != "VAr support"
            data["gen"]["$i"]["alpha"] = gen_total1 / data["gen"]["$i"]["pmax"]
        else
            data["gen"]["$i"]["alpha"] = 0.0
        end
    end

    for i in collect(set2)
        if data["gen"]["$i"]["type"] != "VAr support"
            data["gen"]["$i"]["alpha"] = gen_total2 / data["gen"]["$i"]["pmax"]
        else
            data["gen"]["$i"]["alpha"] = 0.0
        end
    end

    for i in collect(set3)
        if data["gen"]["$i"]["type"] != "VAr support"
            data["gen"]["$i"]["alpha"] = gen_total3 / data["gen"]["$i"]["pmax"]
        else
            data["gen"]["$i"]["alpha"] = 0.0
        end
    end

    for i in collect(set4)
        if data["gen"]["$i"]["type"] != "VAr support"
            data["gen"]["$i"]["alpha"] = gen_total4 / data["gen"]["$i"]["pmax"]
        else
            data["gen"]["$i"]["alpha"] = 0.0
        end
    end

    for i in collect(set5)
        if data["gen"]["$i"]["type"] != "VAr support"
            data["gen"]["$i"]["alpha"] = gen_total5 / data["gen"]["$i"]["pmax"]
        else
            data["gen"]["$i"]["alpha"] = 0.0
        end
    end

    # Adding emergency ac branch ratings and transformer tap and shift bounds 
    for i in parse.(Int64, keys(data["branch"]))
        data["branch"]["$i"]["rate_c"] = 1.3 * data["branch"]["$i"]["rate_c"]
        data["branch"]["$i"]["rate_a"] = data["branch"]["$i"]["rate_c"]
        data["branch"]["$i"]["rate_b"] = data["branch"]["$i"]["rate_c"]
        data["branch"]["$i"]["tm_min"] = tm_min
        data["branch"]["$i"]["tm_max"] = tm_max
        data["branch"]["$i"]["ta_min"] = ta_min
        data["branch"]["$i"]["ta_max"] = ta_max
    end

    # Defining the smoothing coefficient for generator response constraint
    for i in parse.(Int64, keys(data["gen"]))
        data["gen"]["$i"]["ep"] = 1e-1
    end

    # Ading converter dead band voltage bounds and smoothing coefficient for droop constraints
    for i in parse.(Int64, keys(data["convdc"]))
        data["convdc"]["$i"]["ep"] = 1e-1
        data["convdc"]["$i"]["Vdclow"] = 0.98
        data["convdc"]["$i"]["Vdchigh"] = 1.02
    end

    # Empting the data["contingencies"] Dict to save memory  

    data["contingencies"] = []

    # Splitting large coal plant modeled as single generator into units
    if split_large_coal_gens
        split_large_coal_powerplants_to_units!(data)
    end

    # Adding converter convdc["busac_i"])"]["area"]
    for (i, conv) in data["convdc"]
        data["busdc"]["$(conv["busdc_i"])"]["area"] = data["bus"]["$(conv["busac_i"])"]["area"]
    end

    # Setting upper and lower bound of voltage the same for all buses 
    for (i, bus) in data["bus"]
        bus["vmax"] = 1.1
        bus["vmin"] = 0.9
    end

    return data
end

# reassign buses islanded from defined area
function reassign_buses_to_areas(data)
    data["bus"]["57"]["area"] = 2
    data["bus"]["58"]["area"] = 2
    data["bus"]["129"]["area"] = 2
    data["bus"]["231"]["area"] = 2
    data["bus"]["62"]["area"] = 2
    data["bus"]["575"]["area"] = 2
    data["bus"]["10027"]["area"] = 2
    data["bus"]["211"]["area"] = 3
    data["bus"]["349"]["area"] = 3
    data["bus"]["489"]["area"] = 3
    data["bus"]["585"]["area"] = 3
    data["bus"]["587"]["area"] = 3
    data["bus"]["588"]["area"] = 3
    data["bus"]["636"]["area"] = 3
    data["bus"]["986"]["area"] = 4
end

# set pmin values based on unsw predictions
function set_pmin_to_unsw_predictions!(data, fp_unsw_predictions)
    unsw_predictions = CSV.File(fp_unsw_predictions) |> DataFrame
    min_generation = Dict([
        row["Component"] => row["Min Gen (% of nameplate capacity)"]
        for row in eachrow(unsw_predictions)
    ])

    for (g, gen) in data["gen"]
        if gen["name"] ∈ keys(min_generation)
            gen["pmin"] = gen["pmax"] * min_generation[gen["name"]] / 100
        else
            println("$(gen["name"]) not found in min_generation")
        end
        if gen["fuel"] ∈ ["Wind", "Solar"]
            gen["pmin"] = 0.0
        end
    end
end

# set pmin values based on fuel type
# entries in fuel_pmins expressed as ratio to pmax
function set_pmin_values_by_fuel!(data, fuel_pmins)
    for (g, gen) in data["gen"]
        if gen["fuel"] ∈ keys(fuel_pmins)
            gen["pmin"] = fuel_pmins[gen["fuel"]] * gen["pmax"]
        else
            throw(ArgumentError("$(gen["fuel"]) not found in fuel_pmins"))
        end
    end
end

# change branches that should be transformers to transformers
function assign_transformers!(data)
    for (b, branch) in data["branch"]
        if data["bus"]["$(branch["f_bus"])"]["base_kv"] != data["bus"]["$(branch["t_bus"])"]["base_kv"]
            branch["transformer"] = true
        else
            branch["transformer"] = false
        end
    end
end

# stops transmission lines from having variable tap ratios
function set_transmission_line_tap_limits!(data)
    for (b, branch) in data["branch"]
        if branch["transformer"] == false
            branch["tm_min"] = 1.0
            branch["tm_max"] = 1.0
        end
    end
end

# deletes buses that are only connected to a single branch (no gens, loads or shunts)
# also deletes branches that are connected to these buses
function delete_calc_irrelevant_buses!(opf_data)
    # find calc_irrelevant buses
    bus_df = d2d(opf_data["bus"], ["k", "name"])
    bus_df.ind = parse.(Int, bus_df.ind)
    bus_df.gens = zeros(Int, nrow(bus_df))
    bus_df.loads = zeros(Int, nrow(bus_df))
    bus_df.branches = zeros(Int, nrow(bus_df))
    bus_df.shunts = zeros(Int, nrow(bus_df))
    bus_df.convs = zeros(Int, nrow(bus_df))

    # Count elements connected to each bus
    for (g, gen) in opf_data["gen"]
        bus_df[bus_df.ind.==gen["gen_bus"], :gens] .+= 1
    end

    for (l, load) in opf_data["load"]
        bus_df[bus_df.ind.==load["load_bus"], :loads] .+= 1
    end

    for (b, branch) in opf_data["branch"]
        bus_df[bus_df.ind.==branch["f_bus"], :branches] .+= 1
        bus_df[bus_df.ind.==branch["t_bus"], :branches] .+= 1
    end

    for (s, shunt) in opf_data["shunt"]
        bus_df[bus_df.ind.==shunt["shunt_bus"], :shunts] .+= 1
    end

    if haskey(opf_data, "convdc")
        for (c, conv) in opf_data["convdc"]
            bus_df[bus_df.ind.==conv["busac_i"], :convs] .+= 1
        end
    end

    # Identify calc_irrelevant buses
    bus_df.is_calc_irrelevant = (bus_df.gens .== 0) .& (bus_df.loads .== 0) .&
                                (bus_df.branches .== 1) .& (bus_df.shunts .== 0) .&
                                (bus_df.convs .== 0)

    # filter
    filter!(row -> row.is_calc_irrelevant, bus_df)

    # delete buses
    for row in eachrow(bus_df)
        delete!(opf_data["bus"], string(row.ind))
        println("Deleted bus $(row.ind)")
    end

    # delete branches
    branches_to_delete = []
    for (b, branch) in opf_data["branch"]
        if branch["f_bus"] in bus_df.ind || branch["t_bus"] in bus_df.ind
            push!(branches_to_delete, b)
        end
    end

    # delete branches
    for b in branches_to_delete
        delete!(opf_data["branch"], b)
        println("Deleted branch $b")
    end
    return vcat(bus_df.ind, branches_to_delete)
end

# fix NaN values in branch resistance
function fix_nan_branch_resistance!(data)
    for (b, branch) in data["branch"]
        if isequal(branch["br_r"], NaN)
            branch["br_r"] = 0.0
        end
    end
end

# apply power factor constraints
function apply_power_factor_constraints!(data)
    for (g, gen) in data["gen"]
        if gen["gen_status"] == 1 && gen["type"] != "SVC"
            gen["pf_min"] = 0.1
        end
    end
end

# Set generator mbase values so that generators arent operated over 100% of their capacity
# This is done by setting the mbase to the maximum of the real and reactive power limits
function fix_generator_mbase_values!(data)
    for (g, gen) in data["gen"]
        gen["mbase"] = abs(
            gen["pmax"] + 1im * maximum([abs(gen["qmin"]), gen["qmax"]])
        ) * data["baseMVA"]
    end
end

# Set generators with pmax ≈ 0 to be off (mostly REZ generators that have very small capacities)
function turn_off_inactive_generators!(data)
    for (g, gen) in data["gen"]
        if gen["gen_status"] == 1
            if isapprox(gen["pmax"], 0.0, atol=1e-3)
                gen["gen_status"] = 0
                println("$(gen["name"]) has pmax = $(gen["pmax"]), setting gen_status to 0")
            end
        end
    end
end

# turn off loads with negative demand
function turn_off_negative_demand_loads!(data)
    for (l, load) in data["load"]
        if load["pd"] < 0
            load["status"] = 0
            load["pd"] = load["qd"] = 0.0

        end
    end
end

# returns the indexes of the tappable transformers
# these are determined by the voltage levels in the hypersim data
function get_hypersim_tappable_transformers(opf_data, dir_hypersim_csvs)

    # Get 2-winding transformers
    tr2_data = CSV.File(joinpath(dir_hypersim_csvs, "Transformers_2Winding.csv"), header=1, skipto=4) |> DataFrame

    # extract voltage columns
    rename!(
        tr2_data,
        replace.(names(tr2_data), " \r" => "", "\r" => "")
    )
    select!(tr2_data,
        [
            "Component",
            "Primary winding voltage [3]",
            "Secondary winding voltage [3]",
            "Base primary winding voltage",
            "Base secondary winding voltage",
        ]
    )

    rename!(tr2_data, ["name", "V1", "V2", "Vb1", "Vb2"])
    tr2_data.V1 = parse.(Float64, [split(V1, " ")[2] for V1 in tr2_data.V1])
    tr2_data.V2 = parse.(Float64, [split(V2, " ")[2] for V2 in tr2_data.V2])

    tr2_data.V1_diff = tr2_data.V1 ./ tr2_data.Vb1
    tr2_data.V2_diff = tr2_data.V2 ./ tr2_data.Vb2

    filter!(
        row -> !isapprox(row.V1_diff, 1.0, atol=1e-6) && !isapprox(row.V2_diff, 1.0, atol=1e-6),
        tr2_data
    )
    tappable_transformers = tr2_data.name

    # Get 3-winding transformers
    tr3_data = CSV.File(joinpath(dir_hypersim_csvs, "Transformers_3Winding.csv"), header=1, skipto=4) |> DataFrame
    rename!(
        tr3_data,
        replace.(names(tr3_data), " \r" => "", "\r" => "")
    )
    select!(tr3_data,
        [
            "Component",
            "Primary winding voltage [3]",
            "Secondary winding voltage [3]",
            "Base primary winding voltage",
            "Base secondary winding voltage",
            "Base tertiary winding voltage",
            "Tertiary winding voltage [3]",
        ]
    )
    rename!(tr3_data, ["name", "V1", "V2", "Vb1", "Vb2", "Vb3", "V3"])
    tr3_data.V1 = parse.(Float64, [split(V1, " ")[2] for V1 in tr3_data.V1])
    tr3_data.V2 = parse.(Float64, [split(V2, " ")[2] for V2 in tr3_data.V2])
    tr3_data.V3 = parse.(Float64, [split(V3, " ")[2] for V3 in tr3_data.V3])

    tr3_data.V1_diff = tr3_data.V1 ./ tr3_data.Vb1
    tr3_data.V2_diff = tr3_data.V2 ./ tr3_data.Vb2
    tr3_data.V3_diff = tr3_data.V3 ./ tr3_data.Vb3

    filter!(
        row -> !isapprox(row.V1_diff, 1.0, atol=1e-6) && !isapprox(row.V2_diff, 1.0, atol=1e-6) && !isapprox(row.V3_diff, 1.0, atol=1e-6),
        tr3_data
    )

    append!(tappable_transformers, tr3_data.name)

    # Match transformer names to those in the opf data
    tappable_transformers = [join(split(trf_name, "_")[1:end-1], "_") for trf_name in tappable_transformers]
    branch_data = d2d(opf_data["branch"], ["k", "name"])
    sort!(branch_data, :name)

    filter!(
        row -> any(trf_name -> occursin(trf_name, row.name), tappable_transformers),
        branch_data
    )

    return branch_data.ind
end

# set tap limits of transformers in list of tappable transformers
function set_tappable_transformers!(opf_data, tappable_transformers, tm_min=0.9, tm_max=1.1)
    for i in tappable_transformers
        opf_data["branch"]["$i"]["tm_min"] = tm_min
        opf_data["branch"]["$i"]["tm_max"] = tm_max
        opf_data["branch"]["$i"]["transformer"] = true
    end
end

# add a generator to the opf data
function add_gen!(data, gen_bus, gen_parameters; print_added=true)
    gen_keys = [parse(Int, g) for g in keys(data["gen"])]
    new_gen_idx = maximum(gen_keys) + 1

    data["gen"]["$(new_gen_idx)"] = Dict{String,Any}(
        "index" => new_gen_idx,
        "gen_bus" => parse(Int, "$(gen_bus)"),
        "gen_status" => 1,
        "model" => 2,
        "pg" => 0.0,
        "qg" => 0.0,
    )

    for (key, value) in gen_parameters
        data["gen"]["$(new_gen_idx)"][key] = value
    end

    print_added && println("Added generator $(new_gen_idx) to bus $(gen_bus)")

    return data["gen"]["$(new_gen_idx)"]
end

# add a shunt to the opf data
function add_shunt!(data, shunt_bus, shunt_parameters; print_added=true)
    shunt_keys = [parse(Int, s) for s in keys(data["shunt"])]
    new_shunt_idx = maximum(shunt_keys) + 1

    data["shunt"]["$(new_shunt_idx)"] = Dict{String,Any}(
        "index" => new_shunt_idx,
        "shunt_bus" => parse(Int, "$(shunt_bus)"),
        "status" => 1,
        "gs" => 0.0,
        "bs" => 0.0,
    )

    for (key, value) in shunt_parameters
        data["shunt"]["$(new_shunt_idx)"][key] = value
    end

    print_added && println("Added shunt $(new_shunt_idx) to bus $(shunt_bus)")

    return data["shunt"]["$(new_shunt_idx)"]
end

# add an SVC to the opf data
function add_svc!(data, svc_bus, svc_parameters=Dict(); print_added=true)
    default_svc_parameters = Dict(
        "pmax" => 0.0,
        "pmin" => 0.0,
        "qmax" => 0.5,
        "qmin" => -0.5,
        "type" => "SVC",
        "fuel" => "None",
        "cost" => [0.0],
    )

    for (k, v) in svc_parameters
        default_svc_parameters[k] = v
    end

    new_svc = add_gen!(
        data,
        svc_bus,
        default_svc_parameters, # also contains the defined parameters
        print_added=false
    )

    print_added && println("Added SVC $(new_svc["index"]) to bus $(svc_bus)")

    return new_svc
end

# assigns fuel type, cost and max capacity to generators based on custom fuel data
function assign_custom_fuel_mix!(data, custom_fuel_path)
    # parse custom fuel data
    custom_fuels = Dict([
        row["Name"] => Dict(
            "type" => row["Type"],
            "fuel" => row["Fuel"],
            "capacity" => row["Capacity (MW)"],
            "cost" => row["Cost (\$/MWh)"]
        )
        for row in eachrow(CSV.File(custom_fuel_path) |> DataFrame)
    ])

    # assign custom fuel mix to generators
    for (g, gen) in data["gen"]
        if gen["name"] in keys(custom_fuels)
            gen["fuel"] = custom_fuels[gen["name"]]["fuel"]
            gen["cost"] = [custom_fuels[gen["name"]]["cost"], 0.0]
            gen["pmax"] = custom_fuels[gen["name"]]["capacity"] / data["baseMVA"]
            gen["type"] = custom_fuels[gen["name"]]["type"]
        else
            println("Generator $(gen["name"]) not found in custom fuel data")
        end
    end

end

# _PowerModels.update_data! but using the results stored in the CSV files
function update_data_from_opf_csvs!(data, opf_results)
    for row in eachrow(opf_results["branch"])
        # power flows
        data["branch"]["$(row.ind)"]["pf"] = row.pf
        data["branch"]["$(row.ind)"]["qf"] = row.qf
        data["branch"]["$(row.ind)"]["pt"] = row.pt
        data["branch"]["$(row.ind)"]["qt"] = row.qt
        # tap settings
        if "tm_pos_vio" in names(row)
            tm_pos_vio = isequal(row.tm_pos_vio, missing) ? 0.0 : round(row.tm_pos_vio, digits=7)
            tm_neg_vio = isequal(row.tm_neg_vio, missing) ? 0.0 : round(row.tm_neg_vio, digits=7)
            data["branch"]["$(row.ind)"]["tap"] = row.tm + tm_pos_vio - tm_neg_vio
        else
            data["branch"]["$(row.ind)"]["tap"] = row.tm
        end
    end

    for row in eachrow(opf_results["gen"])
        data["gen"]["$(row.ind)"]["pg"] = row.pg
        data["gen"]["$(row.ind)"]["qg"] = row.qg
    end

    for row in eachrow(opf_results["convdc"])
        data["convdc"]["$(row.ind)"]["pdc"] = row.pdc
        data["convdc"]["$(row.ind)"]["pconv"] = row.pconv
        data["convdc"]["$(row.ind)"]["qconv"] = row.qconv
        data["convdc"]["$(row.ind)"]["iconv"] = row.iconv
        data["convdc"]["$(row.ind)"]["pgrid"] = row.pgrid
        data["convdc"]["$(row.ind)"]["qgrid"] = row.qgrid
        data["convdc"]["$(row.ind)"]["ppr_fr"] = row.ppr_fr
        data["convdc"]["$(row.ind)"]["qpr_fr"] = row.qpr_fr
        data["convdc"]["$(row.ind)"]["ptf_to"] = row.ptf_to
        data["convdc"]["$(row.ind)"]["qtf_to"] = row.qtf_to
        data["convdc"]["$(row.ind)"]["vafilt"] = row.vafilt
        data["convdc"]["$(row.ind)"]["vmfilt"] = row.vmfilt
        data["convdc"]["$(row.ind)"]["vaconv"] = row.vaconv
        data["convdc"]["$(row.ind)"]["vmconv"] = row.vmconv
        data["convdc"]["$(row.ind)"]["phi"] = row.phi
    end

    for row in eachrow(opf_results["branchdc"])
        data["branchdc"]["$(row.ind)"]["pf"] = row.pf
        data["branchdc"]["$(row.ind)"]["pt"] = row.pt
    end

    for row in eachrow(opf_results["busdc"])
        data["busdc"]["$(row.ind)"]["vm"] = row.vm
    end

    for vio_name in ["qb_ac_pos_vio", "qb_ac_neg_vio", "pb_ac_pos_vio", "pb_ac_neg_vio"]
        if vio_name in names(opf_results["bus"])
            if any(vio -> !isapprox(vio, 0.0, atol=1e-6), opf_results["bus"][:, vio_name])
                throw(error("Violation of $vio_name found"))
            end
        end
    end

    for row in eachrow(opf_results["bus"])
        data["bus"]["$(row.ind)"]["vm"] = row.vm
        data["bus"]["$(row.ind)"]["va"] = row.va
    end
end


##########################################################################
# Prepares the opf_data NDD for use in the stage 1/stage 2 OPF studies.
##########################################################################

function prepare_opf_data_stage_1(
    scenario, year, snem2000d_dir,
    custom_fuel_path=joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv"),
    hypersim_csv_dir=joinpath(snem2000d_dir, "data", "hypersim_csvs")
)

    ################################################################################
    ################################ DATA_HDVC #####################################
    data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")
    data_file_hvdc = "nem_2300bus_thermal_limits_gen_costs_hvdc_v1.m"

    # Get grid data from the NEM 2000 bus model m-file 
    data_hvdc = _PM.parse_file(joinpath(data_dir, data_file_hvdc))

    # reassign buses islanded from defined area
    reassign_buses_to_areas(data_hvdc)

    # Turn off loads with negative demand
    turn_off_negative_demand_loads!(data_hvdc)

    # Process data to fit into PMACDC model
    _PMACDC.process_additional_data!(data_hvdc)
    # Delete DC lines which have been modelled as AC lines
    _ISP.fix_hvdc_data_issues!(data_hvdc)
    # Assign buses to states
    _ISP.add_area_dict!(data_hvdc)

    # Get generation capacity of REZ and the grid extensions and update grid data
    rez_capacities = _ISP.get_rez_capacity_data(scenario, year; data_dir=data_dir)
    rez_connections = _ISP.get_rez_grid_extensions(; data_dir=data_dir)
    _ISP.add_rez_and_connections!(data_hvdc, rez_connections, rez_capacities,
        max_gen_power=nothing, skip_zero_capacity_rez=false
    )

    # assigns fuel type, cost and max capacity to generators based on custom fuel data
    assign_custom_fuel_mix!(data_hvdc, custom_fuel_path)

    # Add min generation based on unsw predictions
    set_pmin_values_by_fuel!(
        data_hvdc,
        Dict(
            "Black Coal" => 0.1,
            "Brown Coal" => 0.1,
            "Natural Gas" => 0.1,
            "Water" => 0.05,
            "Wind" => 0.05,
            "Solar" => 0.05,
            "NaN" => 0.0,
        )
    )


    ################################################################################
    ################################ OPF_DATA #####################################

    # Make copy of grid data for hourly calculations
    opf_data = deepcopy(data_hvdc)

    # rez_connections["ac"][28, :]
    # Aggregate demand data per state to modulate with hourly traces
    _ISP.aggregate_demand_data!(opf_data)

    # fix data issues, e.g. putting generation cost in € / pu:
    _ISP.fix_data!(opf_data)

    # merge parallel lines
    _ISP.merge_parallel_lines(opf_data)

    # delete buses that are not needed for the calculations (shunt connected to only one branch, with no generators or loads)
    deleted_elms = delete_calc_irrelevant_buses!(opf_data)
    iter_count = 0
    while deleted_elms != [] || iter_count > 100
        deleted_elms = delete_calc_irrelevant_buses!(opf_data)
        iter_count += 1
    end
    if iter_count > 100
        error("Failed to delete all irrelevant buses after 100 iterations")
    end


    # assign transformers based on bus kv
    assign_transformers!(opf_data)

    # set generator mbase values
    fix_generator_mbase_values!(opf_data)

    # turn off inactive generators
    turn_off_inactive_generators!(opf_data)

    # add necessary data for use with scopf (also pfcopf)
    fix_opf_data_issues!(opf_data,
        ta_min=0.0, ta_max=0.0, tm_min=1.0, tm_max=1.0
    )

    # set tap limits based on hypersim data
    hypersim_tappable_transformers = get_hypersim_tappable_transformers(opf_data, hypersim_csv_dir)
    set_tappable_transformers!(opf_data, hypersim_tappable_transformers)

    # set soft tap limits on all other transformers
    for (b, branch) in opf_data["branch"]
        if branch["transformer"] && !(b in hypersim_tappable_transformers)
            branch["soft_tm"] = true
        else
            branch["soft_tm"] = false
        end
    end

    # set switched shunts based on hypersim data
    for (s, shunt) in opf_data["shunt"]
        if startswith(opf_data["shunt_data"][s]["name"], "swSH")
            shunt["switched"] = true
        else
            shunt["switched"] = false
        end
    end

    # cap REG qmin at -1GW
    for (g, gen) in opf_data["gen"]
        if occursin("pv", gen["name"]) || occursin("wtg", gen["name"])
            gen["qmin"] = max(gen["qmin"], -10.0)
        end
    end

    # fix NaN values in branch resistance
    fix_nan_branch_resistance!(opf_data)

    return opf_data

end

function prepare_opf_data_stage_2(
    scenario, year, snem2000d_dir,
    custom_fuel_path=joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv"),
    hypersim_csv_dir=joinpath(snem2000d_dir, "data", "hypersim_csvs")
)

    ################################################################################
    ################################ DATA_HDVC #####################################
    data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")
    data_file_hvdc = "nem_2300bus_thermal_limits_gen_costs_hvdc_v1.m"

    # Get grid data from the NEM 2000 bus model m-file 
    data_hvdc = _PM.parse_file(joinpath(data_dir, data_file_hvdc))

    # reassign buses islanded from defined area
    reassign_buses_to_areas(data_hvdc)

    # Turn off loads with negative demand
    turn_off_negative_demand_loads!(data_hvdc)

    # Process data to fit into PMACDC model
    _PMACDC.process_additional_data!(data_hvdc)
    # Delete DC lines which have been modelled as AC lines
    _ISP.fix_hvdc_data_issues!(data_hvdc)
    # Assign buses to states
    _ISP.add_area_dict!(data_hvdc)

    # Get generation capacity of REZ and the grid extensions and update grid data
    rez_capacities = _ISP.get_rez_capacity_data(scenario, year; data_dir=data_dir)
    rez_connections = _ISP.get_rez_grid_extensions(; data_dir=data_dir)
    _ISP.add_rez_and_connections!(data_hvdc, rez_connections, rez_capacities,
        max_gen_power=nothing, skip_zero_capacity_rez=false
    )

    # assigns fuel type, cost and max capacity to generators based on custom fuel data
    assign_custom_fuel_mix!(data_hvdc, custom_fuel_path)

    # Add min generation based on unsw predictions
    set_pmin_values_by_fuel!(
        data_hvdc,
        Dict(
            "Black Coal" => 0.1,
            "Brown Coal" => 0.1,
            "Natural Gas" => 0.1,
            "Water" => 0.05,
            "Wind" => 0.05,
            "Solar" => 0.05,
            "NaN" => 0.0,
        )
    )


    ################################################################################
    ################################ OPF_DATA #####################################

    # Make copy of grid data for hourly calculations
    opf_data = deepcopy(data_hvdc)

    # rez_connections["ac"][28, :]
    # Aggregate demand data per state to modulate with hourly traces
    _ISP.aggregate_demand_data!(opf_data)

    # fix data issues, e.g. putting generation cost in € / pu:
    _ISP.fix_data!(opf_data)

    # merge parallel lines
    _ISP.merge_parallel_lines(opf_data)

    # delete buses that are not needed for the calculations (shunt connected to only one branch, with no generators or loads)
    deleted_elms = delete_calc_irrelevant_buses!(opf_data)
    iter_count = 0
    while deleted_elms != [] || iter_count > 100
        deleted_elms = delete_calc_irrelevant_buses!(opf_data)
        iter_count += 1
    end
    if iter_count > 100
        error("Failed to delete all irrelevant buses after 100 iterations")
    end


    # assign transformers based on bus kv
    assign_transformers!(opf_data)

    # set generator mbase values
    fix_generator_mbase_values!(opf_data)

    # turn off inactive generators
    turn_off_inactive_generators!(opf_data)

    # add necessary data for use with scopf (also pfcopf)
    fix_opf_data_issues!(opf_data,
        ta_min=0.0, ta_max=0.0, tm_min=1.0, tm_max=1.0
    )

    # set tap limits based on hypersim data
    hypersim_tappable_transformers = get_hypersim_tappable_transformers(opf_data, hypersim_csv_dir)
    stage_1_tappable_transformers = ["1838", "1898", "1888", "1890", "1902", "2513", "3104", "969", "3084", "2160", "3086", "1881", "927", "3137", "1901", "972", "2191", "2221", "514", "2987", "2186", "2254", "2337", "2179", "2403", "3162", "1421", "2225", "2981", "1568", "1419", "2226", "3096", "2153", "2220", "3100", "2996", "2050", "604", "2044", "1528", "1764", "1525", "3093", "2176", "2231", "1689", "1805", "1700", "2183", "1429", "1758", "1431", "1883", "1747", "1807", "1642", "1581", "2171", "2163", "2052", "2197", "2193", "1587", "1903", "2206", "1969"]
    set_tappable_transformers!(opf_data, vcat(hypersim_tappable_transformers, stage_1_tappable_transformers))



    # set soft tap limits on all other transformers
    for (b, branch) in opf_data["branch"]
        if branch["transformer"] && !(b in hypersim_tappable_transformers)
            branch["soft_tm"] = true
        else
            branch["soft_tm"] = false
        end
    end

    # set switched shunts based on hypersim data
    for (s, shunt) in opf_data["shunt"]
        if startswith(opf_data["shunt_data"][s]["name"], "swSH")
            shunt["switched"] = true
        else
            shunt["switched"] = false
        end
    end

    # cap REG qmin at -1GW
    for (g, gen) in opf_data["gen"]
        if occursin("pv", gen["name"]) || occursin("wtg", gen["name"])
            gen["qmin"] = max(gen["qmin"], -10.0)
        end
    end

    # add shunt at bus 2320 (bus 951)
    add_shunt!(opf_data, "951", Dict(
        "bs" => 0.1,
    ))

    # fix NaN values in branch resistance
    fix_nan_branch_resistance!(opf_data)

    return opf_data

end