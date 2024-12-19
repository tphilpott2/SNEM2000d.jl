snem2000d_dir = (@__DIR__) |> dirname |> dirname

########################################################################################
# Analysis functions
########################################################################################

# Make mode df from a row of small signal results
function make_mode_df(row; threshold=0.0)
    states = names(row)[4:end]
    state_names = unique(replace.(states, "_p_mag" => "", "_p_phi" => ""))
    mode_df = DataFrame(
        :state => state_names,
        :p_mag => [row["$(state_name)_p_mag"] for state_name in state_names],
        :p_phi => [row["$(state_name)_p_phi"] for state_name in state_names],
    )

    # filter out one complex conjugate pair
    filter!(row -> row.p_mag >= 0.0, mode_df)

    return mode_df
end

# Make polar plot of a mode
function make_polar_plot(mode_df; threshold=0.1, relayout_params=nothing)

    # filter by threshold
    filter!(row -> row.p_mag > threshold, mode_df)
    traces = AbstractTrace[]
    for row in eachrow(mode_df)
        push!(traces, PlotlyJS.scatter(
            x=[0.0, row.p_mag * cos(rad(row.p_phi))],
            y=[0.0, row.p_mag * sin(rad(row.p_phi))],
            mode="lines",
            name=row.state,
        ))
    end

    pl = PlotlyJS.plot(
        traces,
    )
    if relayout_params != nothing
        PlotlyJS.relayout!(pl, relayout_params)
    end
    return pl
end

# find gens in each mode
function parse_gens_from_states(states)
    gens = replace.(
        states,
        "IEEET1_" => "",
        "TGOV1_" => "",
        "HYGOV_" => "",
        "PSS2B_" => "",
        "REGC_A_" => "",
        "REEC_A_" => "",
        "REEC_B_" => "",
        "PSS2A_" => "",
        "gen" => "Gen",
        "pv" => "PV",
        "wtg" => "WTG",
    )
    gens = [join(split(x, "_")[1:2], " ") for x in gens]
    return sort(unique(gens))
end

# returns a dataframe with the dominant state for each mode in each hour
function get_small_signal_mode_summary(dir, case_list)
    result_df = DataFrame(
        hour=Int[],
        mode_index=Int[],
        real_part=Float64[],
        imag_part=Float64[],
        dominant_gen=String[]
    )
    # Get dominant state for each mode in each hour
    for case in case_list
        # read data
        df = parse_pf_small_signal(small_signal_results_dir, case)
        hour_int = parse(Int, replace(case, "hour_" => ""))
        select_df_cols!(df, [1, 2, 3, "_p_mag"])

        # get dominant state for each mode
        for row in eachrow(df)
            # get dominant states (p_mag == 1)
            dominant_states = [string(state) for state in findall(x -> x == 1.0, row[4:end])]

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

##
########################################################################################
# Read all small signal results, calculate mode summary and make mode dfs
########################################################################################


small_signal_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "small_signal"
)
cases = [replace(fp, ".csv" => "") for fp in readdir(small_signal_results_dir) if !startswith(fp, "header")]
mode_summary_df = get_small_signal_mode_summary(small_signal_results_dir, cases)


mode_dfs = Dict()

# process each case
for case in cases
    case_df = parse_pf_small_signal(small_signal_results_dir, case)

    # # remove one of the complex parts
    # filter!(row -> row.imag_part >= 0.0, case_df)

    # make mode dfs
    mode_dfs[case] = Dict()
    for row in eachrow(case_df)
        mode_df = make_mode_df(row)
        mode_dfs[case][row.mode_index] = mode_df
    end
end

##
########################################################################################
# Make mode classifications
########################################################################################

mode_classification_df = deepcopy(mode_summary_df)

# filter out one complex conjugate pair
filter!(row -> row.imag_part >= 0.0, mode_classification_df)

# classify modes
mode_classification_df.classification = fill("", length(mode_classification_df.dominant_gen))
for row in eachrow(mode_classification_df)
    if row.dominant_gen == "Gen 1038" && isapprox(abs(row.imag_part), 1.0, atol=0.2)
        row.classification = "Gen 1038 Fast"
    elseif row.dominant_gen == "Gen 1038" && isapprox(abs(row.imag_part), 0.1, atol=0.1)
        row.classification = "Gen 1038 Slow"
    elseif row.dominant_gen == "PV Q9"
        row.classification = "PV Q9"
    elseif row.dominant_gen == "Gen 3301"
        row.classification = "Gen 3301"
    elseif row.dominant_gen == "Gen 5031"
        row.classification = "Gen 5031"
    elseif row.dominant_gen == "Gen 5032"
        row.classification = "Gen 5032"
    elseif row.dominant_gen == "WTG Q1"
        row.classification = "WTG Q1"
    elseif row.dominant_gen == "Gen 3456"
        row.classification = "Gen 3456"
    elseif row.dominant_gen == "Gen 3449"
        row.classification = "Gen 3449"
    end
end

##
########################################################################################
# Find gens participating in each classification of mode
########################################################################################

classification_gens = Dict()
participation_threshold = 0.8

for classification in unique(mode_classification_df.classification)
    classification_gens[classification] = []

    # parse modes for classification
    single_class_df = filter(row -> row.classification == classification, mode_classification_df)

    # parse gens for each mode
    for row in eachrow(single_class_df)
        mode_df = deepcopy(mode_dfs["hour_$(lpad(row.hour, 3, '0'))"][row.mode_index])
        filter!(row -> row.p_mag > participation_threshold, mode_df)
        gen_names = parse_gens_from_states(mode_df.state)
        append!(classification_gens[classification], gen_names)
    end

    # remove duplicates
    classification_gens[classification] = unique(classification_gens[classification])
end

for (k, v) in classification_gens
    println(k, " - ", length(v), "\t: ", v)
end

