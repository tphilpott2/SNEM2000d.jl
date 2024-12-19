# imports just the metadata from the results directory
function get_metadata_df(scenario_dir, year; hour_range="All")
    yearly_results = import_yearly_opf_results(scenario_dir, year, hour_range=hour_range)
    return get_metadata_df(yearly_results)
end

"""
Functions to parse the results of the OPF into more useful forms.

This is often a 'time series' of the results throughout the year.
"""

function get_metadata_df(yearly_results)
    metatdata_df = DataFrame(
        :hour => [],
        :termination_status => [],
        :objective => Float64[],
        :solve_time => Float64[],
        :dual_status => [],
        :primal_status => [],
        :objective_lb => [],
    )
    for (hour, hourly_results) in yearly_results
        metadata = hourly_results["metadata"]
        push!(
            metatdata_df,
            (hour, metadata[1, "termination_status"], metadata[1, "objective"], metadata[1, "solve_time"], metadata[1, "dual_status"], metadata[1, "primal_status"], metadata[1, "objective_lb"])
        )
    end
    return metatdata_df
end

function get_trace_bus_vm(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    df_vm = d2d(opf_data["bus"], ["k", "name", "area"])
    df_vm.ind = parse.(Int, df_vm.ind)

    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_vm = select(hourly_results["bus"], [:ind, :vm]) |> DataFrame
            rename!(hourly_vm, :vm => "hour_$hour")
            df_vm = innerjoin(df_vm, hourly_vm, on=:ind)
        end
    end
    return df_vm
end

function get_trace_bus_va(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    df_va = d2d(opf_data["bus"], ["k", "name", "area"])
    df_va.ind = parse.(Int, df_va.ind)

    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_va = select(hourly_results["bus"], [:ind, :va]) |> DataFrame
            rename!(hourly_va, :va => "hour_$hour")
            df_va = innerjoin(df_va, hourly_va, on=:ind)
        end
    end
    return df_va
end

# aggregation just add the violations together for each bus.
function get_trace_bus_p_vio_agg(yearly_results, opf_data; tolerance=6, termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    df_p_vio = d2d(opf_data["bus"], ["k", "name", "area"])
    df_p_vio.ind = parse.(Int, df_p_vio.ind)

    for (hour, hourly_results) in yearly_results
        println(hour)
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            df_bus = copy(hourly_results["bus"])

            # combine positive and negative violations
            df_bus.p_vio = round.(df_bus.pb_ac_pos_vio, digits=tolerance) .- round.(df_bus.pb_ac_neg_vio, digits=tolerance)

            # convert to MW
            df_bus.p_vio = df_bus.p_vio .* opf_data["baseMVA"]

            # add to the dataframes
            select!(df_bus, [:ind, :p_vio])
            rename!(df_bus, :p_vio => "hour_$hour")
            df_p_vio = innerjoin(df_p_vio, df_bus, on=:ind)
        end
    end

    return df_p_vio
end

function get_trace_bus_q_vio_agg(yearly_results, opf_data; tolerance=6, termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    df_q_vio = d2d(opf_data["bus"], ["k", "name", "area"])
    df_q_vio.ind = parse.(Int, df_q_vio.ind)

    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            df_bus = copy(hourly_results["bus"])

            # combine positive and negative violations
            df_bus.q_vio = round.(df_bus.qb_ac_pos_vio, digits=tolerance) .- round.(df_bus.qb_ac_neg_vio, digits=tolerance)

            # convert to MVa
            df_bus.q_vio = df_bus.q_vio .* opf_data["baseMVA"]

            # add to the dataframes
            select!(df_bus, [:ind, :q_vio])
            rename!(df_bus, :q_vio => "hour_$hour")
            df_q_vio = innerjoin(df_q_vio, df_bus, on=:ind)
        end
    end

    return df_q_vio
end

function get_trace_gen_pg(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse generator details from opf_data
    df_gen_p = d2d(opf_data["gen"], ["k", "name", "type", "gen_bus"])
    insertcols!(df_gen_p, 5, :area => [opf_data["bus"]["$(row.gen_bus)"]["area"] for row in eachrow(df_gen_p)])
    select!(df_gen_p, Not(:gen_bus))
    df_gen_p.ind = parse.(Int, df_gen_p.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_gen_p = select(hourly_results["gen"], [:ind, :pg]) |> DataFrame

            # convert to MW
            hourly_gen_p.pg = hourly_gen_p.pg .* opf_data["baseMVA"]

            for gen_ind in df_gen_p.ind
                if gen_ind ∉ hourly_gen_p.ind
                    push!(hourly_gen_p, [gen_ind, 0.0])
                end
            end

            rename!(hourly_gen_p, :pg => "hour_$hour")
            df_gen_p = innerjoin(df_gen_p, hourly_gen_p, on=:ind)
        end
    end

    return df_gen_p
end

function get_trace_gen_qg(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse generator details from opf_data
    df_gen_q = d2d(opf_data["gen"], ["k", "name", "type", "gen_bus"])
    insertcols!(df_gen_q, 5, :area => [opf_data["bus"]["$(row.gen_bus)"]["area"] for row in eachrow(df_gen_q)])
    select!(df_gen_q, Not(:gen_bus))
    df_gen_q.ind = parse.(Int, df_gen_q.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_gen_q = select(hourly_results["gen"], [:ind, :qg]) |> DataFrame

            # convert to MVa
            hourly_gen_q.qg = hourly_gen_q.qg .* opf_data["baseMVA"]

            rename!(hourly_gen_q, :qg => "hour_$hour")
            df_gen_q = innerjoin(df_gen_q, hourly_gen_q, on=:ind)
        end
    end

    return df_gen_q
end

function get_trace_branch_pf(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_pf = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_pf, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_pf)])
    df_branch_pf.ind = parse.(Int, df_branch_pf.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_pf = select(hourly_results["branch"], [:ind, :pf]) |> DataFrame

            # convert to MW
            hourly_branch_pf.pf = hourly_branch_pf.pf .* opf_data["baseMVA"]

            rename!(hourly_branch_pf, :pf => "hour_$hour")
            df_branch_pf = innerjoin(df_branch_pf, hourly_branch_pf, on=:ind)
        end
    end

    return df_branch_pf
end

function get_trace_branch_qf(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_qf = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_qf, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_qf)])
    df_branch_qf.ind = parse.(Int, df_branch_qf.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_qf = select(hourly_results["branch"], [:ind, :qf]) |> DataFrame

            # convert to MVAr
            hourly_branch_qf.qf = hourly_branch_qf.qf .* opf_data["baseMVA"]

            rename!(hourly_branch_qf, :qf => "hour_$hour")
            df_branch_qf = innerjoin(df_branch_qf, hourly_branch_qf, on=:ind)
        end
    end

    return df_branch_qf
end

function get_trace_branch_pt(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_pt = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_pt, 4, :area => [opf_data["bus"]["$(row.t_bus)"]["area"] for row in eachrow(df_branch_pt)])
    df_branch_pt.ind = parse.(Int, df_branch_pt.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_pt = select(hourly_results["branch"], [:ind, :pt]) |> DataFrame

            # convert to MW
            hourly_branch_pt.pt = hourly_branch_pt.pt .* opf_data["baseMVA"]

            rename!(hourly_branch_pt, :pt => "hour_$hour")
            df_branch_pt = innerjoin(df_branch_pt, hourly_branch_pt, on=:ind)
        end
    end

    return df_branch_pt
end

function get_trace_branch_qt(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_qt = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_qt, 4, :area => [opf_data["bus"]["$(row.t_bus)"]["area"] for row in eachrow(df_branch_qt)])
    df_branch_qt.ind = parse.(Int, df_branch_qt.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_qt = select(hourly_results["branch"], [:ind, :qt]) |> DataFrame

            # convert to MVAr
            hourly_branch_qt.qt = hourly_branch_qt.qt .* opf_data["baseMVA"]

            rename!(hourly_branch_qt, :qt => "hour_$hour")
            df_branch_qt = innerjoin(df_branch_qt, hourly_branch_qt, on=:ind)
        end
    end

    return df_branch_qt
end

function get_trace_branch_tm(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_tm = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_tm, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_tm)])
    df_branch_tm.ind = parse.(Int, df_branch_tm.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_tm = select(hourly_results["branch"], [:ind, :tm]) |> DataFrame

            rename!(hourly_branch_tm, :tm => "hour_$hour")
            df_branch_tm = innerjoin(df_branch_tm, hourly_branch_tm, on=:ind)
        else
            println("Skipping hour $hour because of termination status $(hourly_results["metadata"][1, "termination_status"])")
        end
    end

    return df_branch_tm
end

function get_trace_branch_tm_neg_vio(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_tm_neg_vio = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_tm_neg_vio, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_tm_neg_vio)])
    df_branch_tm_neg_vio.ind = parse.(Int, df_branch_tm_neg_vio.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_tm_neg_vio = select(hourly_results["branch"], [:ind, :tm_neg_vio]) |> DataFrame

            rename!(hourly_branch_tm_neg_vio, :tm_neg_vio => "hour_$hour")
            df_branch_tm_neg_vio = innerjoin(df_branch_tm_neg_vio, hourly_branch_tm_neg_vio, on=:ind)
        end
    end

    return df_branch_tm_neg_vio
end

function get_trace_branch_tm_pos_vio(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_tm_pos_vio = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_tm_pos_vio, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_tm_pos_vio)])
    df_branch_tm_pos_vio.ind = parse.(Int, df_branch_tm_pos_vio.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_tm_pos_vio = select(hourly_results["branch"], [:ind, :tm_pos_vio]) |> DataFrame

            rename!(hourly_branch_tm_pos_vio, :tm_pos_vio => "hour_$hour")
            df_branch_tm_pos_vio = innerjoin(df_branch_tm_pos_vio, hourly_branch_tm_pos_vio, on=:ind)
        end
    end

    return df_branch_tm_pos_vio
end

function get_trace_branch_tm_vio_agg(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse branch details from opf_data
    df_branch_tm_vio_agg = d2d(opf_data["branch"], ["k", "f_bus", "t_bus"])
    insertcols!(df_branch_tm_vio_agg, 4, :area => [opf_data["bus"]["$(row.f_bus)"]["area"] for row in eachrow(df_branch_tm_vio_agg)])
    df_branch_tm_vio_agg.ind = parse.(Int, df_branch_tm_vio_agg.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_branch_tm_vio = select(hourly_results["branch"], [:ind, :tm_pos_vio, :tm_neg_vio]) |> DataFrame

            # Aggregate violations by summing positive and negative violations
            hourly_branch_tm_vio.tm_vio_agg = hourly_branch_tm_vio.tm_pos_vio .- hourly_branch_tm_vio.tm_neg_vio

            select!(hourly_branch_tm_vio, [:ind, :tm_vio_agg])
            rename!(hourly_branch_tm_vio, :tm_vio_agg => "hour_$hour")
            df_branch_tm_vio_agg = innerjoin(df_branch_tm_vio_agg, hourly_branch_tm_vio, on=:ind)
        end
    end

    return df_branch_tm_vio_agg
end

function get_trace_busdc_p_vio(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse busdc details from opf_data
    df_busdc_p_vio = d2d(opf_data["busdc"], ["k", "busdc_i"])
    # insertcols!(df_busdc_p_vio, 3, :area => [opf_data["busdc"]["$(row.busdc_i)"]["area"] for row in eachrow(df_busdc_p_vio)])
    df_busdc_p_vio.ind = parse.(Int, df_busdc_p_vio.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_busdc_p_vio = select(hourly_results["busdc"], [:ind, :pb_dc_pos_vio]) |> DataFrame

            rename!(hourly_busdc_p_vio, :pb_dc_pos_vio => "hour_$hour")
            df_busdc_p_vio = innerjoin(df_busdc_p_vio, hourly_busdc_p_vio, on=:ind)
        end
    end

    return df_busdc_p_vio
end

function get_trace_gen_alpha_g(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse generator details from opf_data
    df_gen_alpha_g = d2d(opf_data["gen"], ["k", "gen_bus", "fuel"])
    insertcols!(df_gen_alpha_g, 4, :area => [opf_data["bus"]["$(row.gen_bus)"]["area"] for row in eachrow(df_gen_alpha_g)])
    df_gen_alpha_g.ind = parse.(Int, df_gen_alpha_g.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_gen_alpha_g = select(hourly_results["gen"], [:ind, :alpha_g]) |> DataFrame

            rename!(hourly_gen_alpha_g, :alpha_g => "hour_$hour")
            df_gen_alpha_g = innerjoin(df_gen_alpha_g, hourly_gen_alpha_g, on=:ind)
        end
    end

    return df_gen_alpha_g
end

function get_trace_load_curt(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse generator details from opf_data
    df_load_curt = d2d(opf_data["load"], ["k", "load_bus"])
    insertcols!(df_load_curt, 2, :area => [opf_data["bus"]["$(row.load_bus)"]["area"] for row in eachrow(df_load_curt)])
    df_load_curt.ind = parse.(Int, df_load_curt.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_load_curt = select(hourly_results["load"], [:ind, :load_curt]) |> DataFrame

            rename!(hourly_load_curt, :load_curt => "hour_$hour")
            df_load_curt = innerjoin(df_load_curt, hourly_load_curt, on=:ind)
        end
    end

    return df_load_curt
end

function get_trace_load_pd(yearly_results, opf_data; termination_status=["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED", "ITERATION_LIMIT"])
    # parse load details from opf_data
    df_load_pd = d2d(opf_data["load"], ["k", "load_bus", "pd"])
    insertcols!(df_load_pd, 2, :area => [opf_data["bus"]["$(row.load_bus)"]["area"] for row in eachrow(df_load_pd)])
    df_load_pd.ind = parse.(Int, df_load_pd.ind)

    # parse results
    for (hour, hourly_results) in yearly_results
        if hourly_results["metadata"][1, "termination_status"] in termination_status
            hourly_load_pd = select(hourly_results["load"], [:ind, :pd]) |> DataFrame

            # convert to MW
            hourly_load_pd.pd = hourly_load_pd.pd .* opf_data["baseMVA"]

            rename!(hourly_load_pd, :pd => "hour_$hour")
            df_load_pd = innerjoin(df_load_pd, hourly_load_pd, on=:ind)
        end
    end

    return df_load_pd
end


"""
Overly complicated functions to add traces to the state results dictionary.
"""

function add_traces_to_state_results!(state_results::Dict, trace_df::DataFrame, trace_name::String)
    for state_data in values(state_results)
        state_traces = filter(row -> row.area == state_data["index"], eachrow(trace_df)) |> DataFrame
        state_data["traces"][trace_name] = state_traces
    end
end

function add_traces_to_state_results!(
    state_results::Dict, yearly_results::Union{Dict,OrderedDict}, opf_data::Dict, trace_name::String, trace_func::Function; kwargs...
)
    trace_df = trace_func(yearly_results, opf_data; kwargs...)
    add_traces_to_state_results!(state_results, trace_df, trace_name)
end

function add_traces_to_state_results!(
    state_results::Dict, yearly_results::Union{Dict,OrderedDict}, opf_data::Dict, trace_name::String; kwargs...
)
    trace_func_dict = Dict(
        "bus_p_vio_agg" => get_trace_bus_p_vio_agg,
        "bus_q_vio_agg" => get_trace_bus_q_vio_agg,
        "busdc_p_vio" => get_trace_busdc_p_vio,
        "gen_alpha_g" => get_trace_gen_alpha_g,
        "gen_pg" => get_trace_gen_pg,
        "gen_qg" => get_trace_gen_qg,
        "bus_vm" => get_trace_bus_vm,
        "bus_va" => get_trace_bus_va,
        "load_curt" => get_trace_load_curt,
        "branch_pt" => get_trace_branch_pt,
        "branch_qt" => get_trace_branch_qt,
        "branch_pf" => get_trace_branch_pf,
        "branch_qf" => get_trace_branch_qf,
        "branch_tm" => get_trace_branch_tm,
        "branch_tm_neg_vio" => get_trace_branch_tm_neg_vio,
        "branch_tm_pos_vio" => get_trace_branch_tm_pos_vio,
        "branch_tm_vio_agg" => get_trace_branch_tm_vio_agg,
    )

    if trace_name ∉ keys(trace_func_dict)
        throw(
            ArgumentError(
                "trace_name $(trace_name) must be one of the following: $(keys(trace_func_dict))"
            )
        )
    end

    trace_func = trace_func_dict[trace_name]
    add_traces_to_state_results!(state_results, yearly_results, opf_data, trace_name, trace_func; kwargs...)
end


"""
Utility functions for working with the results of the OPF.
"""

function get_bus_match(data)
    bus_match = Dict()
    for (b, bus) in data["bus"]
        bus_match[bus["index"]] = bus["name"]
        bus_match[bus["name"]] = bus["index"]
    end
    return bus_match
end

function get_trace_hours(df)
    temp_df = DataFrame(:col_names => [x for x in names(df) if occursin("hour_", x)])
    temp_df.hour_idx = [
        parse(Int, split(col_name, "_")[2])
        for col_name in temp_df.col_names
    ]
    sort!(temp_df, :hour_idx)
    return temp_df.col_names
end

function get_trace_hour_range(df)
    return parse.(Int, [split(hour, "_")[2] for hour in get_trace_hours(df)]) |> sort
end

function add_max_column_to_trace!(df)
    if "max" ∉ names(df)
        first_hour_column = findfirst(col -> occursin("hour_", col), names(df))
        insertcols!(df, first_hour_column, :max => zeros(size(df, 1)))
        for row in eachrow(df)
            row.max = maximum([abs(row[hour]) for hour in get_trace_hours(df)])
        end
    end
end

function filter_small_violations!(df; threshold=0.1)
    add_max_column_to_trace!(df)
    sort!(df, :max, rev=true)
    filter!(row -> row.max > threshold, df)
end

function filter_small_violations(df; threshold=0.1)
    temp_df = copy(df)
    filter_small_violations!(temp_df, threshold=threshold)
    return temp_df
end

"""
Plotting functions for the results of the OPF.
"""

function ifkwarg(kwargs, key, default)
    return key ∈ keys(kwargs) ? kwargs[key] : default
end

function get_trace_name(row)
    try
        return row.name
    catch
        try
            return row.ind
        catch
            return nothing
        end
    end
end

function plot_trace_df(trace_df; kwargs...)
    x_series = get_trace_hour_range(trace_df)
    hours = get_trace_hours(trace_df)
    traces = AbstractTrace[]

    for row in eachrow(trace_df)
        y_series = [row[hour] for hour in hours]
        push!(traces, _PLJS.scatter(
            x=x_series,
            y=y_series,
            name=get_trace_name(row),
            mode=ifkwarg(kwargs, :plot_type, "lines"),
            line=attr(width=ifkwarg(kwargs, :line_width, 1)),
            marker=attr(
                size=ifkwarg(kwargs, :marker_size, 2),
                symbol=ifkwarg(kwargs, :marker_symbol, "circle"),
                line_width=ifkwarg(kwargs, :marker_line_width, 1),
                line_color=ifkwarg(kwargs, :marker_line_color, nothing)
            ),
            marker_color=ifkwarg(kwargs, :marker_color, nothing),
        ))
    end

    pl = _PLJS.plot(
        traces,
        Layout(
            title=ifkwarg(kwargs, :title, ""),
            xaxis=attr(title="Hour"),
            yaxis=attr(title=ifkwarg(kwargs, :ylabel, "")),
            margin=attr(l=ifkwarg(kwargs, :left_margin, 10), b=ifkwarg(kwargs, :bottom_margin, 10)),
            showlegend=ifkwarg(kwargs, :showlegend, true)
        )
    )

    return pl
end

function plot_state_results(state_results::Dict, state_name::String, trace_name::String; kwargs...)
    plotting_funcs = Dict(
        "bus_p_vio_agg" => plot_bus_p_vio_agg,
        "bus_q_vio_agg" => plot_bus_q_vio_agg,
        "gen_pg" => plot_gen_pg_by_type,
        "gen_qg" => plot_gen_qg_by_type,
        "bus_vm" => plot_bus_vm,
        "bus_va" => plot_bus_va,
        "branch_tm" => plot_branch_tm,
        "load_curt" => plot_load_curt,
    )

    if trace_name ∉ keys(plotting_funcs)
        throw(ArgumentError(
            "trace_name $(trace_name) must be one of the following for plotting: $(keys(plotting_funcs))"
        ))
    end

    return plotting_funcs[trace_name](
        state_results[state_name]["traces"][trace_name], state_name; kwargs...
    )
end

function plot_bus_p_vio_agg(bus_p_vio_agg::DataFrame, name::String; kwargs...)
    return plot_trace_df(
        bus_p_vio_agg;
        title="Active Power Violations: $name",
        ylabel="Active Power Violation (MW)",
        kwargs...
    )
end

function plot_bus_q_vio_agg(bus_p_vio_agg::DataFrame, name::String; kwargs...)
    return plot_trace_df(
        bus_p_vio_agg;
        title="Reactive Power Violations: $name",
        ylabel="Reactive Power Violation (MVa)",
        kwargs...
    )
end

function plot_bus_vm(bus_vm::DataFrame, name::String; kwargs...)
    return plot_trace_df(
        bus_vm;
        title="Voltage Magnitude: $name",
        ylabel="Voltage Magnitude (p.u)",
        kwargs...
    )
end

function plot_bus_va(bus_va::DataFrame, name::String; kwargs...)
    return plot_trace_df(
        bus_va;
        title="Voltage Angle: $name",
        ylabel="Voltage Angle (rad)",
        kwargs...
    )
end

gen_type_colours = Dict(
    "Fossil" => "black",
    "Thermal" => "black",
    "Hydro" => "blue",
    "Wind" => "green",
    "Solar" => "yellow",
    "SVC" => "orange",
    "NaN" => "grey",
    "Voltage Source" => "red",
)

function plot_gen_pg_by_type(gen_p::DataFrame, name::String; add_rez=true, kwargs...)
    x_series = get_trace_hour_range(gen_p)
    hours = get_trace_hours(gen_p)
    traces = AbstractTrace[]

    for type in unique(gen_p.type)
        type_gen_p = filter(row -> row.type == type, eachrow(gen_p)) |> DataFrame
        y_series = size(type_gen_p, 1) == 0 ? zeros(length(hours)) : [
            sum(type_gen_p[:, hour]) for hour in hours
        ]
        push!(traces, _PLJS.scatter(x=x_series, y=y_series, name=type, line=attr(color=gen_type_colours[type])))
    end

    if add_rez == true
        rez_gen_p = filter(row -> !isnumeric(split(row.name, "_")[2][1]), eachrow(gen_p)) |> DataFrame
        y_series = size(rez_gen_p, 1) == 0 ? zeros(length(hours)) : [
            sum(rez_gen_p[:, hour]) for hour in hours
        ]
        push!(traces, _PLJS.scatter(x=x_series, y=y_series, name="REZ", line=attr(color="red", dash="dot", width=3)))
    end

    pl = _PLJS.plot(
        traces,
        Layout(
            title="Active Power Generation: $name",
            xaxis=attr(title="Hour"),
            yaxis=attr(title="Active Power Generation (MW)"),
            margin=attr(l=ifkwarg(kwargs, :left_margin, 10), b=ifkwarg(kwargs, :bottom_margin, 10)),
            showlegend=true
        )
    )

    return pl
end

function plot_gen_qg_by_type(gen_q::DataFrame, name::String; add_rez=true, kwargs...)
    x_series = get_trace_hour_range(gen_q)
    hours = get_trace_hours(gen_q)
    traces = AbstractTrace[]

    for type in unique(gen_q.type)
        type_gen_q = filter(row -> row.type == type, eachrow(gen_q)) |> DataFrame
        y_series = size(type_gen_q, 1) == 0 ? zeros(length(hours)) : [
            sum(type_gen_q[:, hour]) for hour in hours
        ]
        push!(traces, _PLJS.scatter(x=x_series, y=y_series, name=type, line=attr(color=gen_type_colours[type])))
    end

    if add_rez == true
        rez_gen_q = filter(row -> !isnumeric(split(row.name, "_")[2][1]), eachrow(gen_q)) |> DataFrame
        y_series = size(rez_gen_q, 1) == 0 ? zeros(length(hours)) : [
            sum(rez_gen_q[:, hour]) for hour in hours
        ]
        push!(traces, _PLJS.scatter(x=x_series, y=y_series, name="REZ", line=attr(color="red", dash="dot", width=3)))
    end

    pl = _PLJS.plot(
        traces,
        Layout(
            title="Reactive Power Generation: $name",
            xaxis=attr(title="Hour"),
            yaxis=attr(title="Reactive Power Generation (MW)"),
            margin=attr(l=ifkwarg(kwargs, :left_margin, 10), b=ifkwarg(kwargs, :bottom_margin, 10)),
            showlegend=true
        )
    )

    return pl
end

function plot_load_curt(load_curt::DataFrame, name::String; kwargs...)
    return plot_trace_df(
        load_curt;
        title="Load Curtailment: $name",
        ylabel="Load Curtailment (MW)",
        kwargs...
    )
end

function plot_renewable_penetration(gen_p::DataFrame, name::String; add_rez=true, kwargs...)
    x_series = get_trace_hour_range(gen_p)
    hours = get_trace_hours(gen_p)
    traces = AbstractTrace[]

    gen_df = DataFrame(:hour => hours)
    for type in unique(gen_p.type)
        type_gen_p = filter(row -> row.type == type, eachrow(gen_p)) |> DataFrame
        gen_type_trace = size(type_gen_p, 1) == 0 ? zeros(length(hours)) : [
            sum(type_gen_p[:, hour]) for hour in hours
        ]
        gen_df[!, type] = gen_type_trace
    end

    gen_df.renewable_penetration = zeros(length(hours))

    for row in eachrow(gen_df)
        renewable_generation = row.Wind + row.Solar
        if :Fossil ∈ names(row)
            total_generation = row.Fossil + row.Hydro + row.Wind + row.Solar
        else
            total_generation = row.Thermal + row.Hydro + row.Wind + row.Solar
        end
        row.renewable_penetration = renewable_generation / total_generation
    end

    pl = _PLJS.plot(
        _PLJS.scatter(x=x_series, y=gen_df.renewable_penetration, name="Renewable Penetration"),
        Layout(
            title="Renewable Penetration: $name",
            xaxis=attr(title="Hour"),
            yaxis=attr(title="Active Power Generation (MW)"),
            margin=attr(l=ifkwarg(kwargs, :left_margin, 10), b=ifkwarg(kwargs, :bottom_margin, 10)),
            showlegend=true
        )
    )

    return pl
end

function plot_branch_tm(branch_tm::DataFrame, name::String; kwargs...)
    temp_df = copy(branch_tm)
    # filter out traces where the tap ratio is 1.0 for all hours (transmission lines)
    filter!(row -> !(unique(vec(row[get_trace_hours(temp_df)])) == [1.0]), temp_df)

    return plot_trace_df(
        temp_df;
        title="Transformer Tap Ratios: $name",
        ylabel="Tap Ratio",
        kwargs...
    )
end

function plot_objective_values(metadata_df; termination_status="all", kwargs...)
    traces = GenericTrace[]

    termination_status_colours = Dict(
        "LOCALLY_SOLVED" => "green",
        "ALMOST_LOCALLY_SOLVED" => "blue",
        "ITERATION_LIMIT" => "red",
        "NUMERICAL_ERROR" => "orange",
        "LOCALLY_INFEASIBLE" => "black",
    )

    if termination_status == "all"
        termination_status = unique(metadata_df.termination_status)
    end

    for status in termination_status
        temp_df = filter(row -> row.termination_status == status, metadata_df) |> DataFrame
        if !isempty(temp_df)
            push!(traces, _PLJS.scatter(
                x=parse.(Int, temp_df.hour),
                y=temp_df.objective,
                mode="markers",
                name=status,
                marker=attr(color=get(termination_status_colours, status, nothing)),
            ))
        end
    end

    layout = Layout(
        title=ifkwarg(kwargs, :title, "Objective Value for Each Hour"),
        xaxis_title="Hour",
        yaxis_title="Objective Value",
        xaxis_range=0:maximum(parse.(Int, metadata_df.hour)),
    )

    pl = _PLJS.plot(traces, layout)

    return pl
end

function plot_solve_time(metadata_df; termination_status="all", kwargs...)
    traces = GenericTrace[]

    termination_status_colours = Dict(
        "LOCALLY_SOLVED" => "green",
        "ALMOST_LOCALLY_SOLVED" => "blue",
        "ITERATION_LIMIT" => "purple",
        "NUMERICAL_ERROR" => "orange",
        "LOCALLY_INFEASIBLE" => "red",
    )

    if termination_status == "all"
        termination_status = unique(metadata_df.termination_status)
    end

    for status in termination_status
        temp_df = filter(row -> row.termination_status == status, metadata_df) |> DataFrame
        if !isempty(temp_df)
            push!(traces, _PLJS.scatter(
                x=parse.(Int, temp_df.hour),
                y=temp_df.solve_time,
                mode="markers",
                name=status,
                marker=attr(color=get(termination_status_colours, status, nothing)),
            ))
        end
    end

    layout = Layout(
        title="Solve Time for Each Hour",
        xaxis_title="Hour",
        yaxis_title="Solve Time (seconds)",
        xaxis_range=0:maximum(parse.(Int, metadata_df.hour)),
    )

    pl = _PLJS.plot(traces, layout)

    return pl
end

function plot_demand_series(hour_range, data_dir, scenario="2022 ISP Step Change", year=2050)
    total_demand_series = _ISP.get_demand_data(scenario, year, data_dir)
    traces = AbstractTrace[]

    for (state, timeseries) in total_demand_series
        push!(traces, _PLJS.scatter(
            x=hour_range,
            y=timeseries[hour_range],
            name=state,
            mode="lines",
            line=attr(width=1),
        ))
    end

    pl = _PLJS.plot(
        traces,
        Layout(
            title="Total Demand",
            xaxis=attr(title="Hour"),
            yaxis=attr(title="MW"),
            margin=attr(l=10, b=10),
            showlegend=true
        )
    )
    return pl
end
