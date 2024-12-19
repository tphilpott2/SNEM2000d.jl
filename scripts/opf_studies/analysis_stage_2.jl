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
opf_data = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)

# parse results
results_dir = joinpath(
    snem2000d_dir,
    "results",
    "opf",
    "2050",
    "stage_2",
)
yearly_results = import_yearly_opf_results(results_dir)
metadata_df = get_metadata_df(yearly_results)

##
######################################################################
# Plots of generation by type and renewable penetration for entire nem.
######################################################################
nem_pg_trace = get_trace_gen_pg(yearly_results, opf_data)
pl_gen_pg_by_type = plot_gen_pg_by_type(nem_pg_trace, "Nem - Stage 2", add_rez=false)
pl_renewable_penetration = plot_renewable_penetration(nem_pg_trace, "NEM - Stage 2")
pl_objective = plot_objective_values(get_metadata_df(yearly_results), title="Objective Values")
pl_demand = plot_demand_series(get_trace_hour_range(nem_pg_trace), joinpath(snem2000d_dir, "data", "ISPhvdc"), scenario, year)

combined_plots = [
    pl_gen_pg_by_type;
    pl_renewable_penetration;
    pl_demand;
    pl_objective
]

combined_plots |> display


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

pl_on = Plots.plot(
    gen_counts.hour,
    gen_counts.on_count,
    title="On Count",
    xlabel="Hour",
    ylabel="Count",
    legend=false
)

pl_vio = Plots.plot(
    gen_counts.hour,
    gen_counts.alpha_g_vio,
    title="Alpha G Violations",
    xlabel="Hour",
    ylabel="Count",
    legend=false
)

display(Plots.plot(pl_on, pl_vio, layout=(2, 1)))
