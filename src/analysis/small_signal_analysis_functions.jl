# degree/radian conversions
deg(x) = x * (180 / pi)
rad(x) = x * (pi / 180)

# Make mode df from a row of small signal results
function make_mode_df(row; threshold=0.0)
    states = names(row)[4:end]

    # remove variable descriptions
    state_names = unique(replace.(states,
        "_p_mag" => "",
        "_p_phi" => "",
        "_lEVec_mag" => "",
        "_lEVec_phi" => "",
        "_rEVec_mag" => "",
        "_rEVec_phi" => "",
    ))


    # initialise mode_df
    mode_df = DataFrame(
        :state => state_names,
    )

    # add components that exist in the row
    if any(n -> occursin("p", n), states)
        mode_df.p_mag = [row["$(state_name)_p_mag"] for state_name in state_names]
        mode_df.p_phi = [row["$(state_name)_p_phi"] for state_name in state_names]
    end
    if any(n -> occursin("lEVec", n), states)
        mode_df.lEVec_mag = [row["$(state_name)_lEVec_mag"] for state_name in state_names]
        mode_df.lEVec_phi = [row["$(state_name)_lEVec_phi"] for state_name in state_names]
    end
    if any(n -> occursin("rEVec", n), states)
        mode_df.rEVec_mag = [row["$(state_name)_rEVec_mag"] for state_name in state_names]
        mode_df.rEVec_phi = [row["$(state_name)_rEVec_phi"] for state_name in state_names]
    end

    # parse gen, var and elm from state
    insertcols!(mode_df, 2, :gen => parse_gens_from_states(mode_df.state; sortunqiue=false))
    insertcols!(mode_df, 3, :var => parse_vars_from_states(mode_df.state))
    insertcols!(mode_df, 4, :elm => parse_elms_from_states(mode_df.state))
    select!(mode_df, Not(:state))

    return mode_df
end

# find gens in each mode
function parse_gens_from_states(states; sortunqiue=true)
    gens = replace.(
        states,
        "IEEET1_" => "",
        "TGOV1_" => "",
        "HYGOV_" => "",
        "PSS2B_" => "",
        "REGC_A_" => "",
        "REGC_B_" => "",
        "REEC_A_" => "",
        "REEC_B_" => "",
        "WTGT_A_" => "",
        "PSS2A_" => "",
        "gen" => "Gen",
        "pv" => "PV",
        "wtg" => "WTG",
    )
    gens = [join(split(x, "_")[1:2], " ") for x in gens]
    if sortunqiue
        return sort(unique(gens))
    else
        return gens
    end
end

# returns a dataframe with the dominant state for each mode in each hour
function get_small_signal_mode_summary(small_signal_results_dir, case_list)
    result_df = DataFrame(
        hour=Int[],
        mode_index=Int[],
        real_part=Float64[],
        imag_part=Float64[],
        dominant_gen=String[],
        # other_gens=String[]
    )
    # Get dominant state for each mode in each hour
    for case in case_list
        # read data
        df = parse_powerfactory_small_signal(small_signal_results_dir, case)
        hour_int = parse(Int, replace(case, "hour_" => ""))
        select_df_cols!(df, [1, 2, 3, "_p_mag"])

        # get dominant state for each mode
        for row in eachrow(df)
            # get dominant states (p_mag == 1)
            dominant_states = [string(state) for state in findall(x -> x == 1.0, row[4:end])]
            # other_states = [string(state) for state in findall(x -> x > 0.1, row[4:end])]

            # get gens from dominant states
            dominant_gens = parse_gens_from_states(dominant_states)

            if length(dominant_gens) > 1
                throw(ArgumentError("More than one dominant state for mode $(row.mode_index) in case $(case)"))
            end
            dominant_gen = dominant_gens[1]
            # save
            push!(result_df, (hour_int, row.mode_index, row.real_part, row.imag_part, dominant_gen))
        end
    end

    return result_df
end

# compresses intervals into a nice string for latex table
function get_interval_str(intervals)
    interval_str_vec = []

    in_range = false
    for (idx, interval) in enumerate(sort(intervals))
        if !((interval + 1) in intervals)
            push!(interval_str_vec, "$interval, ")
            in_range = false
        elseif in_range == false
            push!(interval_str_vec, "$interval-")
            in_range = true
        end
    end

    interval_str_vec_fixed = []
    for interval in interval_str_vec
        if endswith(interval, ", ")
            push!(interval_str_vec_fixed, interval)
        elseif endswith(interval, "-")
            i = parse(Int, interval[1:end-1])
            if "$(i+1), " in interval_str_vec
                push!(interval_str_vec_fixed, "$i, ")
            else
                push!(interval_str_vec_fixed, interval)
            end
        else
            throw(ArgumentError("Interval string not formatted correctly: $interval"))
        end
    end

    return join(interval_str_vec_fixed, "")[1:end-2]
end

function parse_gens_from_states(states; sortunqiue=true)
    gens = replace.(
        states,
        "IEEET1_" => "",
        "TGOV1_" => "",
        "HYGOV_" => "",
        "PSS2B_" => "",
        "REGC_A_" => "",
        "REGC_B_" => "",
        "REEC_A_" => "",
        "REEC_B_" => "",
        "WTGT_A_" => "",
        "PSS2A_" => "",
        "gen" => "Gen",
        "pv" => "PV",
        "wtg" => "WTG",
    )
    gens = [join(split(x, "_")[1:2], " ") for x in gens]
    if sortunqiue
        return sort(unique(gens))
    else
        return gens
    end
end

function parse_vars_from_states(states)
    return [split(state, "_")[end] for state in states]
end

function parse_elms_from_states(states)
    vars = parse_vars_from_states(states)
    elms = [replace(state, "_$(var)" => "") for (var, state) in zip(vars, states)]
    return elms
end

function make_polar_plot(
    mode_df;
    var="p",
    threshold=0.1,
    gen_colours::Dict=Dict(),
    title::String="",
    normalise=false,
    var_filter=nothing,
    name="gen",
    kwargs...
)
    # add generator name to mode_df
    temp_df = deepcopy(mode_df)

    # filter by var_filter
    var_filter != nothing && filter!(row -> row.var == var_filter, temp_df)

    # normalise if requested
    if normalise
        temp_df[!, "$(var)_mag"] = temp_df[!, "$(var)_mag"] ./ maximum(temp_df[!, "$(var)_mag"])
    end

    # filter by threshold
    filter!(row -> row["$(var)_mag"] > threshold, temp_df)

    # create plot
    max_mag = maximum(temp_df[!, "$(var)_mag"])
    p = Plots.plot(
        size=(700, 600),
        title=title,
        legend=:outerright,
        projection=:polar,
        lims=(0, max_mag * 1.1);
        kwargs...
    )

    # add traces
    for row in eachrow(temp_df)
        color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        Plots.plot!(
            p,
            [0, rad(row["$(var)_phi"])],  # angles
            [0, row["$(var)_mag"]],       # radii
            label=row[name],
            color=color,
            linewidth=2
        )
    end

    return p
end

function get_gen_colours_by_area(net)
    gen_states = dict_to_dataframe(net["gen"], ["name", "gen_bus"])
    gen_states.state = [net["bus"]["$(row.gen_bus)"]["area"] for row in eachrow(gen_states)]

    gen_states.name = replace.(
        gen_states.name,
        "gen_" => "Gen ",
        "pv_" => "PV ",
        "wtg_" => "WTG ",
    )
    gen_states.name = [split(x, "_")[1] for x in gen_states.name]

    state_colours = Dict(
        1 => "blue",
        2 => "green",
        3 => "red",
        4 => "yellow",
        5 => "purple",
    )

    return Dict(zip(gen_states.name, [state_colours[x] for x in gen_states.state]))
end
