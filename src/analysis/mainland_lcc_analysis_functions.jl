# snem2000d_dir = joinpath(dev_dir(), "SNEM2000d")
# path_res = joinpath(snem2000d_dir, "results", "powerfactory", "mainland_lcc_with_coi_ref")
# opf_res_dir = joinpath(snem2000d_dir, "results", "opf", "2050", "stage_2")
# unstable_osc_plots_dir = joinpath(snem2000d_dir, "results", "mainland_lcc_with_coi_ref_plots", "manual_sort", "unstable")

# state_names = ["NSW", "VIC", "QLD", "SA"]

function get_dir_hypersim_csvs()
    return joinpath(dev_dir(), "SNEM2000d", "data", "hypersim_csvs")
end

"""
Functions for getting data from the nem model
"""

# gets the model and adds powerfactory modelling details
function get_snem_2000d(snem2000d_dir=snem2000d_dir)
    snem2000d = prepare_opf_data_stage_2("2022 ISP Step Change", 2050, snem2000d_dir)
    set_powerfactory_model_types_from_powermodels!(snem2000d)
    for (g, gen) in snem2000d["gen"] # update to use new WECC models
        if gen["powerfactory_model"] == "wind_generator"
            gen["powerfactory_model"] = "WECC_WTG_type_4A"
            gen["WECC_REEC"] = "REEC_A"
            gen["WECC_REGC"] = "REGC_B"
            gen["WECC_PlantControl"] = "REPC_A"
        elseif gen["powerfactory_model"] == "pv_generator"
            gen["powerfactory_model"] = "WECC_PV"
            gen["WECC_REEC"] = "REEC_A"
            gen["WECC_REGC"] = "REGC_B"
            gen["WECC_PlantControl"] = "REPC_A"
        end
    end
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
    return snem2000d
end

# gets gen inertia data from the nem_2000 model (hypersim values)
function get_gen_inertia_df_nem_2000()
    dir_hypersim_csvs = get_dir_hypersim_csvs()
    # parse inertia from hypersim files
    hs_gen_data = CSV.File(joinpath(dir_hypersim_csvs, "Gen.csv"), skipto=4) |> DataFrame
    select!(hs_gen_data, [1, 23])
    rename!(hs_gen_data, [:name, :H])
    return hs_gen_data
end

# gets gen inertia data from the snem2000d model (scaled according to mbase changes)
function get_gen_data_snem2000d(snem2000d)
    df = dict_to_dataframe(snem2000d["gen"], ["name", "k", "powerfactory_model", "gen_bus", "mbase", "H", "fuel"])
    insertcols!(df, 3, :area => [snem2000d["bus"]["$(row.gen_bus)"]["area"] for row in eachrow(df)])
    df.H_pu = df.H .* df.mbase ./ 1000.0
    select!(df, Not(:gen_bus))
    return df
end

# converts inertia from the dataframe to a dictionary
function get_gen_inertia_dict(gen_data_df)
    return Dict([row.name => row.H for row in eachrow(gen_data_df)])
end

# converts inertia_pu from the dataframe to a dictionary 
function get_gen_inertia_dict_pu(gen_data_df)
    return Dict([row.name => row.H_pu for row in eachrow(gen_data_df)])
end

# gets gen data from the nem_2000 model
function get_gen_data_nem_2000(net_in)
    net = deepcopy(net_in)

    # get gen data
    df_gens = dict_to_dataframe(
        net["gen"], [
            "name",
            "mbase",
            "pg",
            "gen_bus",
            "fuel",
            "powerfactory_model"
        ]
    )
    insertcols!(df_gens, 2, :area => [net["bus"][string(row.gen_bus)]["area"] for row in eachrow(df_gens)])

    inertia_dict = get_gen_inertia_dict(get_gen_inertia_df_nem_2000())
    # add inertia to df_gens
    df_gens.H = [
        row.name ∈ keys(inertia_dict) && row.powerfactory_model ∈ ["thermal_generator", "hydro_generator"] ? inertia_dict[row.name] : 0.0
        for row in eachrow(df_gens)
    ]
    df_gens.H_pu = df_gens.H .* df_gens.mbase ./ 1000.0
    return df_gens
end

# maps bus and gen names to area
function get_area_map(net)
    area_map = Dict()
    for (b, bus) in net["bus"]
        area_map[bus["name"]] = bus["area"]
    end

    for (g, gen) in net["gen"]
        area_map[gen["name"]] = net["bus"]["$(gen["gen_bus"])"]["area"]
    end

    return area_map
end

# maps area names to area idxs
function get_area_idxs()
    return Dict(
        "1" => "NSW",
        "2" => "VIC",
        "3" => "QLD",
        "4" => "SA",
        "5" => "TAS",
        1 => "NSW",
        2 => "VIC",
        3 => "QLD",
        4 => "SA",
        5 => "TAS",
        "NSW" => 1,
        "VIC" => 2,
        "QLD" => 3,
        "SA" => 4,
        "TAS" => 5,
    )
end

# maps area names to area colours
function get_area_colours()
    return Dict(
        "NSW" => "blue",
        "VIC" => "green",
        "QLD" => "red",
        "SA" => "yellow",
        "TAS" => "purple",
        1 => "blue",
        2 => "green",
        3 => "red",
        4 => "yellow",
        5 => "purple",
    )
end

function get_load_areas_dict(net)
    load_df = get_load_areas_df(net)
    return Dict([
        row.ind => row.area
        for row in eachrow(load_df)
    ])
end

function get_load_areas_df(net)
    load_df = dict_to_dataframe(net["load"], ["k", "load_bus"])
    load_df.area = [
        net["bus"][string(row.load_bus)]["area"]
        for row in eachrow(load_df)
    ]
    return select(load_df, :ind, :area)
end


"""
Utils and external data handling
"""

function get_case_names(path_res)
    return [replace(x, "header_" => "", ".csv" => "") for x in readdir(path_res)] |> unique
end

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

function split_case_names!(df_res)
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

function add_ibg_penetration!(df; net=snem2000d, opf_res_dir=opf_res_dir)
    opf_results = parse_opf_results(net, opf_res_dir)
    insertcols!(df, 4, :ibg_penetration => [
        100 * opf_results[row.hour]["pg_ibg"] / (opf_results[row.hour]["pg_sg"] + opf_results[row.hour]["pg_ibg"])
        for row in eachrow(df)
    ])
end

function add_stability_col!(df; end_time=20.0)
    insertcols!(df, 4, :stable => [
        row.end_time == end_time && !(row.out_of_step) && row.δ_stab && !(row.overspeed) && !(row.underspeed)
        for row in eachrow(df)
    ])
end

function add_stability_category!(df; unstable_osc_plots_dir=nothing, end_time=20.0, clear=true)
    if "osc_stability" ∉ names(df)
        add_unstable_osc!(df, unstable_osc_plots_dir)
    end

    :stability_category ∈ propertynames(df) && select!(df, Not(:stability_category))
    insertcols!(df, 4, :stability_category => fill("", size(df, 1)))
    for row in eachrow(df)
        if row.end_time != end_time
            row.stability_category = "Crashed"
        elseif row.out_of_step || !row.δ_stab || !row.osc_stability || row.overspeed || row.underspeed
            row.stability_category = "Unstable"
        else
            row.stability_category = "Stable"
        end
    end

    clear && select!(df, Not(:out_of_step, :δ_stab, :osc_stability, :overspeed, :underspeed))
end

function add_fcas_surplus!(df, fcas_data, hourly_fcas_data)
    # get shortfall data and calculate total fcas
    shortfall_df = get_fcas_summary_df(fcas_data)
    shortfall_df.total_fcas = shortfall_df.fcas_procured .+ shortfall_df.sg_fcas
    fcas_dict = Dict([
        row.hour => row.total_fcas * 100
        for row in eachrow(shortfall_df)
    ])

    # add fcas surplus to df (not including disturbance gen)
    insertcols!(df, 4,
        :fcas_surplus => [
            fcas_dict[row.hour] - row.disturbance_size
            for row in eachrow(df)
        ]
    )

    # subtract any fcas from disturbance gen
    for row in eachrow(df)
        # check if falted gen is contributing fcas
        if row.disturbance_gen ∈ fcas_data[row.hour]["fcas_ibgs"]
            idx = findfirst(r -> r.name == row.disturbance_gen, eachrow(hourly_fcas_data[row.hour]))
            fcas_row = hourly_fcas_data[row.hour][idx, :]
            row.fcas_surplus = row.fcas_surplus - (fcas_row.pmax - fcas_row.pg) * 100
        end
    end
end

function add_inertia!(df, snem_2000d; path_res=path_res, pu=false, Sb=100)
    gen_data = get_gen_data_snem2000d(snem_2000d)
    gen_inertias = get_gen_inertia_dict_pu(gen_data)
    insertcols!(df, 4, :inertia => fill(0.0, size(df, 1)))

    for row in eachrow(df)
        case_name = get_case_name(row)

        # get active sgs
        header = parse_powerfactory_header(joinpath(path_res, "header_$(case_name).csv"))
        active_sgs = filter(r -> r.var == "s:fipol", header).elm

        # get inertia
        row.inertia = sum(map(gen -> gen_inertias[gen], active_sgs))
        if !pu
            row.inertia = row.inertia * Sb
        end
    end
end

get_case_name(row::DataFrameRow) = "hour_$(lpad(row.hour, 3, '0'))-$(row.disturbance_gen)-$(Int64(row.disturbance_size))MW"

"""
Plotting
"""

function plot_coi(case_name, inertia_dict; path_res=path_res, kwargs...)
    df = parse_powerfactory_rms(path_res, case_name, vars=["s:speed"])
    df.coi = get_coi_freq(
        df, inertia_dict;
        disturbance_gen=split(case_name, "-")[2]
    )
    pl = Plots.plot(
        df.time, df.coi .* 50;
        size=_MS, legend=false,
        lw=2,
        kwargs...
    )
    return pl
end

function plot_coi!(case_name, inertia_dict; path_res=path_res, kwargs...)
    df = parse_powerfactory_rms(path_res, case_name, vars=["s:speed"])
    df.coi = get_coi_freq(
        df, inertia_dict;
        disturbance_gen=split(case_name, "-")[2]
    )
    Plots.plot!(
        df.time, df.coi .* 50;
        size=_MS, legend=false,
        lw=2,
        kwargs...
    )
end

function plot_speed(case_name; path_res=path_res, kwargs...)
    df = parse_powerfactory_rms(path_res, case_name, vars=["s:speed"])

    # remove disturbance gen
    disturbance_gen = split(case_name, "-")[2]
    if "$(disturbance_gen)_speed" in names(df)
        select!(df, Not("$(disturbance_gen)_speed"))
    end


    pl = plot_pf(
        n -> 50 * n, df;
        size=_MS, legend=false,
        lw=2,
        kwargs...
    )
    return pl
end

function plot_speed_coloured(
    case_name;
    gen_data=gen_data, path_res=path_res, kwargs...
)
    df = parse_powerfactory_rms(path_res, case_name, vars=["s:speed"])

    # remove disturbance gen
    disturbance_gen = split(case_name, "-")[2]
    if "$(disturbance_gen)_speed" in names(df)
        select!(df, Not("$(disturbance_gen)_speed"))
    end

    # group by area
    temp_gen_data = deepcopy(gen_data)
    gen_names = replace.(names(df)[2:end], "_speed" => "")
    filter!(r -> r.name in gen_names, temp_gen_data)

    # set area colors
    area_cols = Dict(
        1 => :blue,
        2 => :green,
        3 => :red,
        4 => :yellow,
    )

    # make plot
    pl = Plots.plot(
        size=_MS, legend=false;
        kwargs...
    )

    for row in eachrow(temp_gen_data)
        area = row.area
        pl = plot_pf!(
            n -> 50 * n, df_speed, "$(row.name)_speed";
            lw=2,
            c=area_cols[area]
        )
    end

    return pl
end

function add_frequency_bands!(pl)
    frequency_bands = OrderedDict(
        "Normal Operating Frequency Band" => Dict(
            "range" => [49.85, 50.15],
            "color" => :green,
        ),
        "Normal Operating Frequency Excursion Band" => Dict(
            "range" => [49.75, 49.85],
            "color" => :blue,
        ),
        "Operating Frequency Tolerance Band" => Dict(
            "range" => [49.0, 49.75],
            "color" => :orange,
        ),
        "Extreme Frequency Excursion Tolerance Limit" => Dict(
            "range" => [47.0, 49.0],
            "color" => :red,
        ),
    )

    # Add frequency bands in reverse order (so normal band is on top)
    for (name, band) in reverse(collect(frequency_bands))
        Plots.hspan!(
            pl,
            band["range"],
            alpha=0.15,
            color=band["color"],
            label=name
        )
    end
end

function plot_three_params(
    df,
    x_axis_param,
    y_axis_param,
    col_param;
    x_axis_label=x_axis_param,
    y_axis_label=y_axis_param,
    colbar_label=col_param,
    cmap=Plots.cgrad([:green, :yellow, :red], rev=false),
    kwargs...
)
    pl_three = Plots.scatter(
        df[!, x_axis_param],
        df[!, y_axis_param],
        zcolor=df[!, col_param];
        xlabel=x_axis_label,
        ylabel=y_axis_label,
        colorbar_title=colbar_label,
        label=false,
        legend=false,
        colorbar=true,
        c=cmap,
        grid=true,
        gridalpha=0.3,
        framestyle=:box,
        leftmargin=(5, :mm),
        rightmargin=(5, :mm),
        bottommargin=(5, :mm),
        shape=:circle,
        msw=0,
        markersize=3,
        fontfamily="Times Roman",
        xtickfontsize=15,
        ytickfontsize=15,
        xlabelfontsize=20,
        ylabelfontsize=20,
        legendfontsize=20,
        colorbar_titlefontsize=20,
        size=(1200, 800),
        kwargs...
    )

    return pl_three
end


"""
Stability checks and data analysis
"""

function process_time_series_results(path_res, gen_data; case_list=nothing, end_time=20.0)
    # get case list
    if case_list === nothing
        cases = get_case_names(path_res)
    else
        cases = case_list
    end

    # get inertia dictionary
    inertia_dict = get_gen_inertia_dict(gen_data)

    # initialise results dataframe
    df_res = DataFrame(
        :case => String[],
        :δ_stab => Bool[],
        :overspeed => Bool[],
        :underspeed => Bool[],
        :end_time => Float64[],
        :out_of_step => Bool[],
        :out_of_step_time => Float64[],
        :nadir => Float64[],
        :nadir_time => Float64[],
    )

    problem_cases = String[]
    df_speed = DataFrame()
    for (i, case) in enumerate(cases)
        println("$i: Processing $case")
        # load results
        try
            df_speed = parse_powerfactory_rms(path_res, case, vars=["s:speed"])
        catch
            println("Error parsing $case")
            push!(problem_cases, case)
            continue
        end

        # check end time
        if df_speed.time[end] != end_time
            push!(df_res, (
                    case,
                    false,
                    false,
                    false,
                    df_speed.time[end],
                    false,
                    0.0,
                    0.0,
                    0.0,
                ), promote=true)
            continue
        end

        # check out of step with firel
        df_firel = parse_powerfactory_rms(path_res, case, vars=["s:firel"])
        out_of_step, out_of_step_time = is_out_of_step(df_firel)

        # check rotor angle stability
        df_fipol = parse_powerfactory_rms(path_res, case, vars=["s:fipol"])
        δ_stable = check_rotor_angle_stability(df_fipol)

        # check for overspeed and underspeed
        overspeed = check_for_overspeed(df_speed; threshold=50.5, t_range=(0, end_time))
        underspeed = check_for_underspeed(df_speed; threshold=47.0, t_range=(0, end_time))

        # get nadir
        coi_freq = get_coi_freq(df_speed, inertia_dict) .* 50
        nadir = minimum(coi_freq)
        nadir_time = df_speed.time[argmin(coi_freq)]

        # return data
        push!(df_res, (
                case,
                δ_stable,
                overspeed,
                underspeed,
                df_speed.time[end],
                out_of_step,
                out_of_step_time,
                nadir,
                nadir_time,
            ), promote=true)
    end

    # split case names
    split_case_names!(df_res)

    return df_res, problem_cases
end

function get_avg_speed(df::DataFrame)
    temp = deepcopy(df)
    select!(temp, Not(:time))
    select_df_cols!(temp, ["speed"])
    avg_speed = [
        mean(row[2:end])
        for row in eachrow(temp)
    ]
    return avg_speed
end

function check_rotor_angle_stability(df::DataFrame)
    # filter columns
    temp = deepcopy(df)
    select!(temp, Not(:time))
    select_df_cols!(temp, ["fipol"])

    # check if data is empty
    if isempty(temp)
        throw(ArgumentError("No rotor angle data found"))
    end

    # check if any rotor angle is 180 degrees
    return !any(
        any(x -> isapprox(x, 180.0, atol=2.0), col_data)
        for col_data in eachcol(temp))
end

function get_peaks(value_vec::Vector{Float64}, time_vec::Vector{Float64}; Hz=false)
    # get minima and maxima with prominence filtering
    minima_data = findminima(value_vec)
    maxima_data = findmaxima(value_vec)
    minima = DataFrame(
        :index => minima_data.indices,
        :value => minima_data.heights,
    )
    maxima = DataFrame(
        :index => maxima_data.indices,
        :value => maxima_data.heights,
    )

    # get peaks
    peaks = vcat(minima, maxima)
    sort!(peaks, :index)
    peaks.time = time_vec[peaks.index]
    select!(peaks, :time, :value)

    # convert to Hz if requested
    if Hz
        peaks.value = peaks.value .* 50
    end

    return peaks
end

function check_for_overspeed(df::DataFrame; threshold=50.5, t_range=(-Inf, Inf))
    temp = deepcopy(df)
    filter!(r -> r.time .> t_range[1] && r.time .< t_range[2], temp)

    # check for overspeed
    for (col_name, col_data) in pairs(eachcol(temp))
        col_name == :time && continue
        if any(col_data .> threshold / 50)
            return true
        end
    end
    return false
end

function check_for_underspeed(df::DataFrame; threshold=49.5, t_range=(-Inf, Inf))
    temp = deepcopy(df)
    filter!(r -> r.time .> t_range[1] && r.time .< t_range[2], temp)

    # check for overspeed
    for (col_name, col_data) in pairs(eachcol(temp))
        col_name == :time && continue
        if any(col_data .< threshold / 50)
            return true
        end
    end
    return false
end

function check_oscillatory_stability(df::DataFrame, nadir::Float64; threshold=0.5, t_filter=10.0)
    peak_df = deepcopy(df)

    # Calculate amplitudes (difference between consecutive peaks)
    peak_df.value = peak_df.value
    peak_df.amplitudes = vcat(0, abs.(diff(peak_df.value)))

    # scale amplitudes according to first peak (nadir)
    peak_df.scaled_amplitudes = peak_df.amplitudes ./ (50 - nadir)

    # filter out peaks before filter time
    filter!(r -> r.time .> t_filter, peak_df)

    # check if any amplitude exceeds threshold (weakly decayed or unstable oscillations)
    stable = any(peak_df.scaled_amplitudes .> threshold) ? false : true
    return stable
end

# get frequency nadir
function get_nadir(coi_freq, t_vec; t_range=(-Inf, Inf), Hz=true)
    df = DataFrame(
        :time => t_vec,
        :coi => coi_freq,
    )
    filter!(r -> r.time .> t_range[1] && r.time .< t_range[2], df)
    if Hz
        return minimum(df.coi) * 50, df.time[findall(r -> r.coi == minimum(df.coi), eachrow(df))][1]
    else
        return minimum(df.coi), df.time[findall(r -> r.coi == minimum(df.coi), eachrow(df))][1]
    end
end

function is_out_of_step(df_firel; angle_diff=360, angle_tol=10)
    # calculate the differnces between each time step for each column
    diff_df = DataFrame(:time => df_firel.time[2:end])
    for col_name in names(df_firel)[2:end]
        diff_df[!, col_name] = diff(df_firel[!, col_name])
    end

    # check if any of the differences are close to the set magnitude
    out_of_step = any(
        col -> any(angle -> isapprox(abs(angle), angle_diff, atol=angle_tol), col),
        eachcol(diff_df)
    ) ? true : false

    # if out of step, find the first time step that is out of step
    out_of_step_time = 0.0
    if out_of_step
        idx = findfirst(row -> any(x -> isapprox(abs(x), angle_diff, atol=angle_tol), row), eachrow(diff_df))
        out_of_step_time = diff_df.time[idx]
    end

    return out_of_step, out_of_step_time
end

function add_unstable_osc!(df, unstable_osc_plots_dir)
    unstable_osc = replace.(readdir(unstable_osc_plots_dir), ".png" => "")
    df.osc_stability = [
        get_case_name(row) in unstable_osc ? false : true
        for row in eachrow(df)
    ]
end

# calculates COI frequency from a time series results dataframe and inertia dictionary
# uses all synchronous machines in the time series results if sym_names is not provided
function get_coi_freq(
    time_series_results, inertia_dict;
    sym_names=[],
    disturbance_gen=nothing
)
    # copy the time series results
    df = deepcopy(time_series_results)

    # get synchronous machines in time series dataframe
    if isempty(sym_names)
        sym_names = replace.(
            names(df)[findall(x -> endswith(x, "_speed"), names(df))],
            "_speed" => ""
        )
    end

    # remove disturbance gen if provided
    if !isequal(disturbance_gen, nothing)
        filter!(r -> r != disturbance_gen, sym_names)
    end

    # get time vector
    # calculate COI frequency

    Ht = sum(inertia_dict[sym_name] for sym_name in sym_names) # sauer and pai uses Mt
    ω_coi = zeros(size(df, 1)) # initialise COI frequency vector

    for sym_name in sym_names
        gen_speed = df[!, Symbol(sym_name * "_speed")]
        weighted_speed = gen_speed .* inertia_dict[sym_name]
        ω_coi += weighted_speed
    end

    ω_coi = ω_coi ./ Ht
    return ω_coi
end

