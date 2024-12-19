# filepaths
snem2000d_dir = (@__DIR__) |> dirname |> dirname # package directory
isphvdc_data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc") # isphvdc data
custom_fuel_path = joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv") # nem2000d custom fuels

# load package
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

# configure scenario
scenario = "2022 ISP Step Change"
year = 2050
hour_range = 1:1
n_procs = 4

# define results directory
results_dir = joinpath(
    snem2000d_dir,
    "results",
    "opf",
    "$year",
    "stage_1",
)


# parse opf_data (yearly data for the ISPhvdc scenario) and ISPhvdc time series data
opf_data = prepare_opf_data_stage_1(scenario, year, snem2000d_dir)
isphvdc_time_series = get_ISPhvdc_time_series(scenario, year, isphvdc_data_dir)

# define variable bounds
opf_data["variable_bounds"] = Dict(
    "qb_ac_pos_vio" => 0.05,
    "qb_ac_neg_vio" => 0.05,
)

# define soft variable costs (and bigM values)
opf_data["soft_var_costs"] = Dict(
    "alpha_g" => 10,
    "shunt_bigM" => 10,
    "vm_cost" => 100,
    "qb_pos" => 5e3,
    "qb_neg" => 5e3,
    "tm_pos" => 1e3,
    "tm_neg" => 1e3,
)

# run opfs
addprocs_if_needed(n_procs)
run_hourly_opfs_multiprocessing(
    hour_range,
    run_uc_soft_q_soft_tap_switched_shunt,
    opf_data,
    isphvdc_time_series,
    results_dir;
    max_iter=5000,
    n_procs=n_procs,
    skip_existing=true,
)

##
##############################################################
## Secondary runs, for those that did not successfully solve
##############################################################
res_dir_secondary = joinpath(results_dir, "..", "..", "$year", "stage_1_reruns")
mkdir_if(res_dir_secondary)

#################################
# locally infeasible 
#################################
metadata_df = get_metadata_df(import_yearly_opf_results(results_dir))
filter!(row -> row.termination_status ∉ ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"], metadata_df) |> println
locally_infeasible_hours = parse.(Int, [row.hour for row in eachrow(metadata_df) if row.termination_status == "LOCALLY_INFEASIBLE"])

opf_data["variable_bounds"] = Dict(
    "qb_ac_pos_vio" => 0.1,
    "qb_ac_neg_vio" => 0.1,
)

run_hourly_opfs(
    locally_infeasible_hours,
    run_uc_soft_q_soft_tap_switched_shunt,
    opf_data,
    isphvdc_time_series,
    res_dir_secondary;
    max_iter=5000,
    # n_procs=n_procs,
    skip_existing=true,
)

#################################
# numerical error
#################################
metadata_df = get_metadata_df(import_yearly_opf_results(results_dir, year))
filter!(row -> row.termination_status ∉ ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"], metadata_df) |> println
numerical_error_hours = parse.(Int, [row.hour for row in eachrow(metadata_df) if row.termination_status == "NUMERICAL_ERROR"])

opf_data["variable_bounds"] = Dict(
    "qb_ac_pos_vio" => 0.05,
    "qb_ac_neg_vio" => 0.05,
)

opf_data["soft_var_costs"] = Dict(
    "alpha_g" => 10,
    "shunt_bigM" => 10,
    "vm_cost" => 10,
    "qb_pos" => 5e3,
    "qb_neg" => 5e3,
    "tm_pos" => 1e3,
    "tm_neg" => 1e3,
)

run_hourly_opfs(
    numerical_error_hours,
    run_uc_soft_q_soft_tap_switched_shunt,
    opf_data,
    isphvdc_time_series,
    res_dir_secondary;
    max_iter=5000,
    # n_procs=n_procs,
    skip_existing=false,
)

#################################
# iteration limit
#################################
metadata_df = get_metadata_df(import_yearly_opf_results(results_dir, year))
filter!(row -> row.termination_status ∉ ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"], metadata_df) |> println
iteration_limit_hours = parse.(Int, [row.hour for row in eachrow(metadata_df) if row.termination_status == "ITERATION_LIMIT"])

opf_data["variable_bounds"] = Dict(
    "qb_ac_pos_vio" => 0.05,
    "qb_ac_neg_vio" => 0.05,
)

opf_data["soft_var_costs"] = Dict(
    "alpha_g" => 10,
    "shunt_bigM" => 10,
    "vm_cost" => 10,
    "qb_pos" => 5e3,
    "qb_neg" => 5e3,
    "tm_pos" => 1e3,
    "tm_neg" => 1e3,
)

run_hourly_opfs(
    iteration_limit_hours,
    run_uc_soft_q_soft_tap_switched_shunt,
    opf_data,
    isphvdc_time_series,
    res_dir_secondary;
    max_iter=5000,
    # n_procs=n_procs,
    skip_existing=false,
)