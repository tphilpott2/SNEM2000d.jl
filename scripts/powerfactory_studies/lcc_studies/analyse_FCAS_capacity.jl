function get_parent_dir(parent_dir::String, child_dir::String)
    println("searching for $parent_dir from $child_dir")
    dir_path = child_dir
    last_dir = dir_path
    while !endswith(dir_path, parent_dir)
        dir_path = dirname(dir_path)
        last_dir == dir_path && throw(ArgumentError("Package $parent_dir not found. last dir: $dir_path"))
        last_dir = dir_path
    end
    return dir_path
end
snem2000d_dir = get_parent_dir("SNEM2000d", @__DIR__)
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

function parse_opf_results(net, opf_res_dir)
    all_scenarios = Dict()
    for hour in 1:144
        # parse data from opf results
        gen_data = CSV.File(joinpath(opf_res_dir, "$hour", "gen.csv")) |> DataFrame
        filter!(r -> !isapprox(r.alpha_g, 0.0, atol=1e-6), gen_data)

        # add areas and fuel types to gen data
        gen_data = innerjoin(
            gen_data,
            dict_to_dataframe(net["gen"], ["index", "fuel", "gen_bus"]),
            on=:ind => :index,
        )

        # remove non-mainland gens
        insertcols!(
            gen_data,
            :area => [
                net["bus"]["$(r.gen_bus)"]["area"]
                for r in eachrow(gen_data)
            ],
        )
        filter!(r -> r.area != 5, gen_data)

        # compute total synchronous generation
        synchronous_generation = sum(
            filter(r -> r.fuel ∈ [
                    "Black Coal",
                    "Brown Coal",
                    "Natural Gas",
                    "Water",
                ], gen_data).pg
        )

        # compute inverter generation
        inverter_generation = sum(
            filter(r -> r.fuel ∈ [
                    "Solar",
                    "Wind",
                ], gen_data).pg
        )

        # load load data
        df_load = CSV.File(joinpath(opf_res_dir, "1", "load.csv")) |> DataFrame

        # add areas to load data
        df_load = innerjoin(
            df_load,
            dict_to_dataframe(snem2000d["load"], ["index", "load_bus"]),
            on=:ind => :index,
        )
        df_load.area = [snem2000d["bus"]["$(r.load_bus)"]["area"] for r in eachrow(df_load)]

        # filter out tas and loads that are off
        filter!(r -> r.area != 5, df_load)
        filter!(r -> r.status == 1, df_load)

        # compute total load
        total_load = sum(df_load.pd)


        all_scenarios[hour] = Dict(
            "pg_sg" => synchronous_generation,
            "pg_ibg" => inverter_generation,
            "pd" => total_load,
        )
    end

    return all_scenarios
end

function process_time_series_results(path_res)

    cases = [replace(x, "header_" => "", ".csv" => "") for x in readdir(path_res)]

    df_res = DataFrame(
        :case => String[],
        :rotor_angle_stability => Bool[],
        :end_time => Float64[],
        # :n_minima => Int[],
        :minima => DataFrame[],
    )

    for (i, case) in enumerate(cases)
        println("$i: Processing $case")
        # load results
        df_speed = parse_pf_rms(path_res, case, vars=["s:speed"])
        df_fipol = parse_pf_rms(path_res, case, vars=["s:fipol"])

        # check stability
        stable = !any(
            any(x -> isapprox(x, 180.0, atol=2.0), col_data)
            for col_data in eachcol(df_fipol))

        # compute average speed
        df_speed.avg_speed = [
            mean(row[2:end])
            for row in eachrow(df_speed)
        ]

        # get minima of average speed
        minima_data = findminima(df_speed.avg_speed)
        minima = DataFrame(
            :index => minima_data.indices,
            :value => minima_data.heights,
        )

        push!(df_res, (case, stable, df_speed.time[end], minima))

        # pl_speed = plot_pf(df_speed, size=_MS, title=case, frame=:box, legend=false)
        # pl_fipol = plot_pf(df_fipol, size=_MS, title=case, frame=:box, legend=false)
        # plot(pl_speed, pl_fipol, size=_MS) |> display
        # i > 10 && break
    end
    return df_res
end

function parse_case_names!(df_res)
    # parse hour
    insertcols!(df_res, 1, :hour => [
        split(row.case, "-")[1]
        for row in eachrow(df_res)
    ])
    df_res.hour = [parse(Int, split(r.hour, "_")[2]) for r in eachrow(df_res)]

    # parse disturbance gen
    insertcols!(df_res, 2, :disturbance_gen => [
        split(row.case, "-")[2]
        for row in eachrow(df_res)
    ])

    # parse disturbance size
    insertcols!(df_res, 3, :disturbance_size => [
        parse(Float64, replace(split(row.case, "-")[end], "MW" => ""))
        for row in eachrow(df_res)
    ])

    # remove case column
    select!(df_res, Not(:case))
end

function get_gen_dispatch(net, opf_res_dir)
    gen_dispatch = Dict([
        g => DataFrame(
            :hour => Int[],
            :status => Int[],
            :pg => Float64[],
        )
        for (g, _) in net["gen"]
    ])
    for hour in 1:144
        # parse data from opf results
        gen_data = CSV.File(joinpath(opf_res_dir, "$hour", "gen.csv")) |> DataFrame

        # add status
        gen_data.status = [
            isapprox(r.alpha_g, 0.0, atol=1e-6) ? 0 : 1
            for r in eachrow(gen_data)
        ]

        # add dispatch data
        for row in eachrow(gen_data)
            push!(gen_dispatch[string(row.ind)], (
                hour,
                row.status,
                row.status == 0 ? 0.0 : row.pg
            ))
        end
    end

    return gen_dispatch
end

function get_gen_capacities(snem2000d, isphvdc_time_series, opf_res_dir)
    gen_capacities = Dict([
        g => DataFrame(
            :hour => Int[],
            :pmax => Float64[],
        )
        for (g, _) in snem2000d["gen"]
    ])

    for hour in 1:144
        # copy opf data for hourly calculations
        hourly_data = deepcopy(snem2000d)

        # prepare hourly data
        _ISP.prepare_hourly_opf_data!(
            hourly_data,
            snem2000d,
            isphvdc_time_series.total_demand_series,
            isphvdc_time_series.average_demand_per_state,
            isphvdc_time_series.pv_series,
            isphvdc_time_series.wind_series,
            isphvdc_time_series.pv_rez,
            isphvdc_time_series.wind_rez,
            hour
        )

        for (g, gen) in hourly_data["gen"]
            push!(gen_capacities[g], (hour, gen["pmax"]))
        end
    end

    return gen_capacities
end

function transpose_gen_data(gen_data, snem2000d)
    hourly_data = Dict([
        hour => DataFrame(
            :index => Int[],
            :status => Int[],
            :pg => Float64[],
            :pmax => Float64[],
        )
        for hour in 1:144
    ])

    for (g, g_data) in gen_data
        for row in eachrow(g_data)
            push!(hourly_data[row.hour], (parse(Int, g), row.status, row.pg, row.pmax))
        end
    end

    df_gens = dict_to_dataframe(snem2000d["gen"], ["index", "fuel", "name", "gen_bus"])
    df_gens.area = [snem2000d["bus"]["$(r.gen_bus)"]["area"] for r in eachrow(df_gens)]

    # hourly_data_df = deepcopy(hourly_data)

    for (hour, hourly_data_df) in hourly_data
        hourly_data[hour] = innerjoin(
            hourly_data_df,
            df_gens,
            on=:index
        )
        select!(hourly_data[hour], [
            :index,
            :name,
            :area,
            :fuel,
            :status,
            :pg,
            :pmax,
        ])
    end

    return hourly_data
end

function get_fcas_generators(state_data_df; fcas_multiplier=1.0)
    # filter out isolated generators
    filter!(r -> r.name ∉ ["wtg_N2_1",
            "pv_N2_1",
            "wtg_N4_1",
            "pv_N4_1",
            "wtg_Q6_1",
            "pv_Q6_1",
        ], state_data_df
    )
    filter!(r -> r.area != 5, state_data_df) # filter out non-mainland gens
    filter!(r -> r.status == 1, state_data_df) # filter out out of service gens

    # compute loading and available capacity
    state_data_df.loading = state_data_df.pg ./ state_data_df.pmax
    state_data_df.available_capacity = state_data_df.pmax - state_data_df.pg

    # find LCC
    lcc = maximum(state_data_df.pg)
    # # filter out lcc gen
    # filter!(r -> r.pg != lcc, state_data_df)

    # filter for in service synchronous machines
    sg_df = filter(r -> r.fuel ∈ ["Black Coal", "Brown Coal", "Natural Gas", "Water"], state_data_df) |> DataFrame

    # filter out gens with loading > 90%
    filter!(r -> r.loading < 0.9, sg_df)

    # compute available capacity
    sg_available_capacity = sum(sg_df.pmax - sg_df.pg)
    # sg_available_capacity = 0.0
    ibg_fcas_required = (lcc - sg_available_capacity) * fcas_multiplier

    # filter out non-mainland gens, out of service gens and non-ibgs
    ibg_df = filter(r -> r.fuel ∈ ["Wind", "Solar"], state_data_df) |> DataFrame
    # filter!(r -> startswith(r.name, "wtg") || startswith(r.name, "pv"), state_data_df)

    # filter out gens with loading > 90%
    filter!(r -> r.loading < 0.9, ibg_df)

    # determine IBGs to provide FCAS
    sort!(ibg_df, :loading)
    # sort!(ibg_df, :available_capacity, rev=true)

    fcas_procured = 0.0
    fcas_ibgs = []
    for row in eachrow(ibg_df)
        push!(fcas_ibgs, row.name)
        fcas_procured += row.available_capacity
        if fcas_procured >= ibg_fcas_required
            break
        end
    end
    return fcas_ibgs, fcas_procured, lcc
end

function write_fcas_ibg_csv(fcas_data, optput_fp)
    open(optput_fp, "w") do f
        for (hour, data) in fcas_data
            write(f, "$hour,$(join(data["fcas_ibgs"], ","))\n")
        end
    end
    println("Wrote $optput_fp")
end

function add_loading_and_available_capacity!(df)
    df.loading = df.pg ./ df.pmax
    df.available_capacity = df.pmax - df.pg
end

function get_fcas_data_df(fcas_data::Union{Dict,OrderedDict})
    return vcat([fcas_data[hour]["summary"] for hour in 1:144]...)
end

function get_fcas_summary_df(fcas_data_df::DataFrame)
    gdf = groupby(fcas_data_df, :hour)

    summary_df = combine(
        gdf,
        :fcas_procured => sum => :fcas_procured,
        :sg_fcas => sum => :sg_fcas,
        :ibg_fcas_required => maximum => :fcas_required,
        :lcc => maximum => :lcc_max,
    )

    summary_df.shortfall = summary_df.lcc_max .- summary_df.fcas_procured .- summary_df.sg_fcas


    sort!(summary_df, :hour, rev=true)
    return summary_df
end

function get_fcas_summary_df(fcas_data::Union{Dict,OrderedDict})
    fcas_data_df = get_fcas_data_df(fcas_data)
    return get_fcas_summary_df(fcas_data_df)
end

function procure_ibgs(ibg_df::DataFrame, ibg_fcas_required::Float64)
    fcas_procured = 0.0
    fcas_ibgs = []
    for row in eachrow(ibg_df)
        if fcas_procured >= ibg_fcas_required
            break
        end
        push!(fcas_ibgs, row.name)
        fcas_procured += row.available_capacity
    end
    return fcas_ibgs, fcas_procured
end

function procure_fcas_for_state(state_data_df::DataFrame)
    # compute loading and available capacity
    add_loading_and_available_capacity!(state_data_df)

    # find LCC and filter out of state data
    lcc = maximum(state_data_df.pg)
    lcc_gen = state_data_df.name[state_data_df.pg.==lcc][1]
    filter!(r -> r.pg != lcc, state_data_df)

    # filter for in service synchronous machines and filter out gens with loading > 90%
    sg_df = filter(r -> r.fuel ∈ ["Black Coal", "Brown Coal", "Natural Gas", "Water"], state_data_df) |> DataFrame
    filter!(r -> r.status == 1, sg_df) # filter out out of service gens
    filter!(r -> r.loading < 0.9, sg_df)

    # compute required FCAS from IBGs
    sg_available_capacity = sum(sg_df.pmax - sg_df.pg)
    ibg_fcas_required = max((lcc - sg_available_capacity) * fcas_multiplier, 0.0)

    # filter out non-mainland gens, out of service gens and non-ibgs
    ibg_df = filter(r -> r.fuel ∈ ["Wind", "Solar"], state_data_df) |> DataFrame
    filter!(r -> r.loading < 0.9, ibg_df)
    filter!(r -> r.status == 1, ibg_df)

    # determine IBGs to provide FCAS
    sort!(ibg_df, :available_capacity, rev=true)

    fcas_ibgs, fcas_procured = procure_ibgs(ibg_df, ibg_fcas_required)

    return fcas_ibgs, lcc, lcc_gen, sg_available_capacity, ibg_fcas_required, fcas_procured
end

##
"""
Get required data for FCAS procurement
"""

# file paths
opf_res_dir = joinpath(snem2000d_dir, "results", "opf", "2050", "stage_2")
data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")

# load nem model
snem2000d = prepare_opf_data_stage_2("2022 ISP Step Change", 2050, snem2000d_dir)
for (g, gen) in snem2000d["gen"]
    # set wind and solar inertia to 0
    if gen["fuel"] ∈ ["Wind", "Solar"]
        gen["H"] = 0.0
    end
    # convert string to float
    if typeof(gen["H"]) != Float64
        gen["H"] = parse(Float64, gen["H"])
    end
end

# load dispatch of opf cases
opf_results = parse_opf_results(snem2000d, opf_res_dir)

# load isphvdc time series
isphvdc_time_series = get_ISPhvdc_time_series("2022 ISP Step Change", 2050, data_dir)

# get dispatch of each gen in each case
gen_dispatch = get_gen_dispatch(snem2000d, opf_res_dir)

# get max capacity of each gen in each scenario
gen_capacities = get_gen_capacities(snem2000d, isphvdc_time_series, opf_res_dir)

# join dispatch and capacity data
gen_data = deepcopy(gen_capacities)
for (g, g_data) in gen_capacities
    gen_data[g] = innerjoin(
        g_data,
        gen_dispatch[g],
        on=:hour => :hour,
    )
end

# add loading to gen data
for (g, g_data) in gen_data
    g_data.loading = [
        (row.pmax == 0.0) || (row.status == 0) ? -1 : row.pg / row.pmax
        for row in eachrow(g_data)
    ]
end

# transpose to sort data by hour rather than gen
hourly_data = transpose_gen_data(gen_data, snem2000d)

##
"""
FCAS procurement
"""

# initialise data structures
fcas_data = OrderedDict()
hourly_fcas_ibgs = OrderedDict()
fcas_multiplier = 1.0 # multiplier for FCAS procurement. should be set to 1

# procure FCAS for each scenario
for hour in 1:144
    # initialise data structures
    hourly_fcas_ibgs[hour] = []
    fcas_data[hour] = Dict(
        "summary" => DataFrame(
            :hour => [],
            :area => [],
            :lcc => [],
            :lcc_gen => [],
            :sg_fcas => [],
            :ibg_fcas_required => [],
            :fcas_procured => [],
        ),
        "fcas_ibgs" => [],
    )
    hourly_data_df = deepcopy(hourly_data[hour])
    filter!(r -> r.area != 5, hourly_data_df)

    # group and procure FCAS by area
    gdf = groupby(hourly_data_df, :area)
    for g in gdf
        state_data_df = deepcopy(g) |> DataFrame

        # filter out isolated generators
        filter!(r -> r.name ∉ ["wtg_N2_1",
                "pv_N2_1",
                "wtg_N4_1",
                "pv_N4_1",
                "wtg_Q6_1",
                "pv_Q6_1",
            ], state_data_df
        )
        filter!(r -> r.area != 5, state_data_df) # filter out non-mainland gens
        filter!(r -> r.pmax > 0.0, state_data_df) # filter out out of service gens

        # run first pass of FCAS procurement (state level)
        # procure_fcas_for_state!(fcas_data, state_data_df, hour)
        (fcas_ibgs, lcc, lcc_gen, sg_fcas, ibg_fcas_required, fcas_procured) = procure_fcas_for_state(state_data_df)

        # add IBGs to FCAS procured list
        append!(fcas_data[hour]["fcas_ibgs"], fcas_ibgs)

        # add data to summary df
        push!(
            fcas_data[hour]["summary"],
            [
                hour,
                g.area[1],
                lcc,
                lcc_gen,
                sg_fcas,
                ibg_fcas_required,
                fcas_procured,
            ],
        )
    end

    # calculate shortfall and procure more FCAS if required
    shortfall = maximum(fcas_data[hour]["summary"].lcc) - sum(fcas_data[hour]["summary"].fcas_procured) - sum(fcas_data[hour]["summary"].sg_fcas)
    if shortfall > 0.0
        # filter out gens that are out of service, the LCC gen, not IBGs, or already procured FCAS
        available_fcas_df = filter(r -> r.status == 1, hourly_data_df) |> DataFrame
        filter!(r -> r.name != fcas_data[hour]["summary"].lcc_gen, available_fcas_df)
        filter!(r -> r.name ∉ fcas_data[hour]["fcas_ibgs"], available_fcas_df)
        filter!(r -> r.fuel ∈ ["Wind", "Solar"], available_fcas_df)

        # calculate available capacity and filter out gens with loading > 90%
        add_loading_and_available_capacity!(available_fcas_df)
        filter!(r -> r.loading < 0.9, available_fcas_df)

        # calculate overshoot
        available_fcas_df.overshoot = available_fcas_df.available_capacity .- shortfall

        # find available FCAS from in service IBGs, not including LCC gen and already procured FCAS
        if any(r -> r.overshoot > 0.0, eachrow(available_fcas_df)) # procure FCAS from single machine
            # filter out gens that wont cover the shortfall
            filter!(r -> r.overshoot > 0.0, available_fcas_df)

            # sort for lowest overshoot
            sort!(available_fcas_df, :overshoot)

            # add the gen that will cover the shortfall
            push!(fcas_data[hour]["fcas_ibgs"], available_fcas_df.name[1])

            fcas_data[hour]["summary"][
                findall(r -> r == available_fcas_df.area[1], fcas_data[hour]["summary"].area)[1],
                :fcas_procured] += available_fcas_df.available_capacity[1]

            fcas_data[hour]["shortfall"] = 0.0
        else # procure FCAS from multiple machines
            fcas_procured = 0.0
            fcas_ibgs = []
            for row in eachrow(available_fcas_df)
                if fcas_procured >= shortfall
                    break
                end
                push!(fcas_ibgs, row.name)
                fcas_procured += row.available_capacity
            end

            # add additional FCAS procured
            append!(fcas_data[hour]["fcas_ibgs"], fcas_ibgs)

            fcas_data[hour]["shortfall"] = shortfall > fcas_procured ? shortfall - fcas_procured : 0.0
        end
    end
end

# write FCAS IBGs to csv
write_fcas_ibg_csv(fcas_data, joinpath(snem2000d_dir, "data", "mainland_fcas_ibgs_2050.csv"))

# get summary of FCAS procurement
summary_df = get_fcas_summary_df(fcas_data)
hourly_fcas_data = deepcopy(hourly_data)
