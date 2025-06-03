# file paths
snem2000d_dir = (@__DIR__) |> dirname |> dirname |> dirname
data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")
custom_fuel_path = joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv")

# load SNEM2000d
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

# configure scenario and year
scenario = "2022 ISP Step Change"
year = 2025
for year in 2026:2049
    hour_range = 1:72
    n_procs = 4

    # define results directory
    results_dir = joinpath(
        snem2000d_dir,
        "results",
        "opf",
        "more_setpoints",
        "$year",
    )
    if !isdir(results_dir)
        mkdir(results_dir)
    end

    # parse opf_data (yearly data for the ISPhvdc scenario) and ISPhvdc time series data
    opf_data = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)
    isphvdc_time_series = get_ISPhvdc_time_series(scenario, year, data_dir)


    # define soft variable costs
    opf_data["soft_var_costs"] = Dict(
        "alpha_g" => 10,
        "shunt_bigM" => 10,
        "vm_cost" => 100,
    )

    # run opfs
    addprocs_if_needed(n_procs)
    run_hourly_opfs_multiprocessing(
        hour_range,
        run_uc_oltc_switched_shunt,
        opf_data,
        isphvdc_time_series,
        results_dir;
        max_iter=5000,
        n_procs=n_procs,
        skip_existing=true,
    )
end