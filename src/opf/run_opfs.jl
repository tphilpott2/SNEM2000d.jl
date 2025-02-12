##########################################################################
# Functions for running bulk OPFs
##########################################################################

# adds processes for use in multiprocessing
function addprocs_if_needed(n_procs)
    if length(workers()) < n_procs
        if workers() == [1]
            addprocs(n_procs)
        else
            addprocs(n_procs - (length(workers()) - 1))
        end
        println("Added workers: $(workers())")
    else
        println("Enough workers already")
    end
end

# runs opfs for a given hour range
function run_hourly_opfs(
    hour_range,
    opf_function,
    opf_data,
    isphvdc_time_series,
    results_dir;
    max_iter=6000,
    skip_existing=true,
    export_load_demand=true,
    solver=nothing
)
    println("Running hourly OPFs for hours: $hour_range")
    opf_result = hourly_data = nothing
    for hour in hour_range
        println("Processing hour $hour")
        # skip if already run
        if skip_existing && isfile(joinpath(results_dir, string(hour), "metadata.csv"))
            println("Skipping hour $hour")
            continue
        end

        # make directory for hourly results
        hour_dir = joinpath(results_dir, string(hour))
        if isdir(hour_dir) == false
            mkdir(hour_dir)
            println("Created: '$hour_dir'")
        else
            println("Already exists: '$hour_dir'")
        end

        # copy opf data for hourly calculations
        hourly_data = deepcopy(opf_data)

        # prepare hourly data
        _ISP.prepare_hourly_opf_data!(
            hourly_data,
            opf_data,
            isphvdc_time_series.total_demand_series,
            isphvdc_time_series.average_demand_per_state,
            isphvdc_time_series.pv_series,
            isphvdc_time_series.wind_series,
            isphvdc_time_series.pv_rez,
            isphvdc_time_series.wind_rez,
            hour
        )

        # Solver settings
        if solver === nothing
            solver = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "max_iter" => max_iter)
        end

        println("running OPF")
        # run the OPF
        opf_result = opf_function(hourly_data, _PM.ACPPowerModel, solver)


        # Export results
        println("Exporting results for hour $hour")
        export_hourly_opf_result(
            hour_dir,
            opf_result
        )
        if export_load_demand
            export_hourly_load_demand(
                hour_dir,
                hourly_data
            )
        end
    end
    return opf_result, hourly_data
end

# runs opfs for a given hour range in parallel
function run_hourly_opfs_multiprocessing(
    hours,
    opf_function,
    opf_data,
    isphvdc_time_series,
    results_dir;
    max_iter=6000,
    skip_existing=true,
    n_procs=6,
    export_load_demand=true,
    solver=nothing
)
    addprocs_if_needed(n_procs)

    @everywhere include(joinpath(dirname(@__DIR__), "SNEM2000d.jl"))


    # Distribute the hour range across workers
    chunk_size = ceil(Int, length(hours) / n_procs)
    hour_chunks = [hours[i:min(i + chunk_size - 1, end)] for i in 1:chunk_size:length(hours)]

    @sync @distributed for chunk in hour_chunks
        run_hourly_opfs(
            chunk,
            opf_function,
            opf_data,
            isphvdc_time_series,
            results_dir;
            max_iter=max_iter,
            skip_existing=skip_existing,
            export_load_demand=export_load_demand,
            solver=solver
        )
    end
end

##########################################################################
# IO functions to CSVs for OPF results.
##########################################################################

function get_result_variables(class_results::Dict)
    all_vars = String[]
    for v in values(class_results)
        append!(all_vars, [k for k in keys(v)])
    end
    return unique(all_vars)
end

function export_hourly_opf_result(output_dir, opf_result)
    output_dfs = Dict()
    for (class, class_results) in opf_result["solution"]
        if class_results isa Dict
            output_dfs[class] = dict_to_dataframe(
                class_results,
                vcat(["k"], get_result_variables(class_results)),
                add_missing_vars=true
            )
            sort!(output_dfs[class], :ind)
        end
    end
    output_dfs["metadata"] = DataFrame(
        "solve_time" => opf_result["solve_time"],
        "termination_status" => string(opf_result["termination_status"]),
        "dual_status" => string(opf_result["dual_status"]),
        "primal_status" => string(opf_result["primal_status"]),
        "objective" => opf_result["objective"],
        "objective_lb" => opf_result["objective_lb"],
    )
    for (name, df) in output_dfs
        CSV.write(joinpath(output_dir, "$name.csv"), df)
    end
end

function export_hourly_load_demand(output_dir, hourly_data)
    df = dict_to_dataframe(hourly_data["load"], ["k", "status", "pd", "qd"])
    df.ind = parse.(Int, df.ind)
    sort!(df, :ind)
    CSV.write(joinpath(output_dir, "load.csv"), df)
end

function import_hourly_opf_result(hour_dir)
    return Dict([
        replace(file_name, ".csv" => "") => CSV.File(joinpath(hour_dir, file_name)) |> DataFrame
        for file_name in readdir(hour_dir)
    ])
end

function import_yearly_opf_results(yearly_results_dir; hour_range="All")
    if hour_range == "All"
        hour_range = parse.(
            Int,
            [
                hr for hr in readdir(yearly_results_dir)
                if "metadata.csv" ∈ readdir(joinpath(yearly_results_dir, hr))
            ]
        )
    end
    return OrderedDict([
        string(hour) => import_hourly_opf_result(
            joinpath(
                yearly_results_dir,
                string(hour)
            )
        )
        for hour in hour_range
    ])
end
