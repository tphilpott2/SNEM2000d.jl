# file paths
snem2000d_dir = (@__DIR__) |> dirname |> dirname
isphvdc_data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")
custom_fuel_path = joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv")

# load SNEM2000d
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

# define scenario and year
scenario = "2022 ISP Step Change"
year = 2050

# load opf_data
opf_data = prepare_opf_data_stage_1(scenario, year, snem2000d_dir)


######################################################################
# Parses results of stage 1 studies.
# Re-runs use the same formulation as the first run but with different costs/soft var bounds.
# Values are in run_stage_1_opfs.jl
######################################################################

# paths
results_dir = joinpath(
    snem2000d_dir,
    "results",
    "opf",
    "2050",
    "stage_1",
)
rerun_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "opf",
    "2050",
    "stage_1_reruns",
)

# import results of first run
yearly_results = import_yearly_opf_results(results_dir)
metadata_df = get_metadata_df(yearly_results)

# add rerun results (overwrite first run results)
rerun_hours = parse.(Int, [row.hour for row in eachrow(metadata_df) if row.termination_status ∉ ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"]])
for hour in rerun_hours
    yearly_results[string(hour)] = import_hourly_opf_result(
        joinpath(rerun_results_dir, string(hour))
    )
end

# redo metadata
metadata_df = get_metadata_df(yearly_results)

##
######################################################################
# Plots of generation by type and renewable penetration for entire nem.
######################################################################

nem_pg_trace = get_trace_gen_pg(yearly_results, opf_data)
pg_by_fuel_plot = plot_gen_pg_by_type(nem_pg_trace, "Nem - Stage 1", add_rez=false)
renewable_penetration_plot = plot_renewable_penetration(nem_pg_trace, "NEM - Stage 1")
pl_objective = plot_objective_values(get_metadata_df(yearly_results), title="Objective Values")
pl_demand = plot_demand_series(get_trace_hour_range(nem_pg_trace), joinpath(snem2000d_dir, "data", "ISPhvdc"), scenario, year)

combined_plots = [
    pg_by_fuel_plot;
    renewable_penetration_plot;
    pl_demand;
    pl_objective_stage_1
]

combined_plots |> display

##
######################################################################
# Plot Power Balance Violations
######################################################################

q_vio_traces = get_trace_bus_q_vio_agg(yearly_results, opf_data)

# filter small violations
filter_small_violations!(q_vio_traces, threshold=1e-8)
pl_q_vio = plot_trace_df(q_vio_traces, title="Q Violations") |> display

##
######################################################################
# TAP RATIOS:
######################################################################

tm_trace = get_trace_branch_tm(yearly_results, opf_data)
hours = get_trace_hours(tm_trace)
filter!(row -> unique(row[hours]) != [1.0], tm_trace)
pl_tm = plot_trace_df(tm_trace, title="Tap Ratios")

tm_pos_vio_trace = get_trace_branch_tm_pos_vio(yearly_results, opf_data)
tm_neg_vio_trace = get_trace_branch_tm_neg_vio(yearly_results, opf_data)
sort!(tm_pos_vio_trace, :ind)
sort!(tm_neg_vio_trace, :ind)
tm_vio_trace = select(tm_pos_vio_trace, [:ind, :f_bus, :t_bus])
for hour in hours
    # replace missings with 0
    tm_pos_vio_trace[!, hour] = coalesce.(tm_pos_vio_trace[:, hour], 0)
    tm_neg_vio_trace[!, hour] = coalesce.(tm_neg_vio_trace[:, hour], 0)
    tm_vio_trace[!, hour] = tm_pos_vio_trace[:, hour] .- tm_neg_vio_trace[:, hour]
end
filtered_tm_vio_trace = filter_small_violations(tm_vio_trace, threshold=1e-2)
# filter!(row -> row.max <= 0.03, filtered_tm_vio_trace)


pl_tap_vios = plot_trace_df(
    filtered_tm_vio_trace,
    title="Tap Violations",
)


combined_plot = [
    pl_tm;
    pl_tap_vios;
    pl_objective_stage_1
]

display(combined_plot)

println("Number of transformers with violations: ", nrow(filtered_tm_vio_trace))
clipboard(string.(filtered_tm_vio_trace.ind))

##
######################################################################
# Generator counts
######################################################################

hours = sort(parse.(Int, keys(yearly_results)))
n_gens = count(gen["gen_status"] != 0 for gen in values(opf_data["gen"]))

gen_counts = DataFrame(
    :hour => hours,
    :on_count => [
        count(row -> isapprox(row.alpha_g, 1.0, atol=1e-6), eachrow(yearly_results[string(hour)]["gen"]))
        for hour in hours
    ],
    :off_count => [
        count(row -> isapprox(row.alpha_g, 0.0, atol=1e-6), eachrow(yearly_results[string(hour)]["gen"]))
        for hour in hours
    ],
    :termination_status => [
        yearly_results[string(hour)]["metadata"][1, "termination_status"]
        for hour in hours
    ]
)
gen_counts.alpha_g_vio = n_gens .- (gen_counts.on_count .+ gen_counts.off_count)
filter!(row -> row.termination_status in ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"], gen_counts)

pl_on = _PL.plot(
    gen_counts.hour,
    gen_counts.on_count,
    title="On Count",
    xlabel="Hour",
    ylabel="Count",
    legend=false
)

pl_vio = _PL.plot(
    gen_counts.hour,
    gen_counts.alpha_g_vio,
    title="Alpha G Violations",
    xlabel="Hour",
    ylabel="Count",
    legend=false
)

display(_PL.plot(pl_on, pl_vio, layout=(2, 1)))