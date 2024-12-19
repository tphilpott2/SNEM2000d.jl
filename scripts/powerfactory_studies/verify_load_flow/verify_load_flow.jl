snem2000d_dir = (@__DIR__) |> dirname |> dirname |> dirname

# load package
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))


# define scenario and year
scenario = "2022 ISP Step Change"
year = 2050
hour_range = 1:144
# load network
# nem_2000_isphvdc = prepare_opf_data_stage_2_final(scenario, year, nem_2000_isphvdc_dir, custom_fuel_path)

# make comparison plots
for hour in hour_range
    df_bus = plot_bus_voltage_comparison(
        joinpath(snem2000d_dir, "results", "load_flow_verification", "hour_$(lpad(hour, 3, '0'))"),
        joinpath(snem2000d_dir, "results", "opf", "2050", "stage_2", string(hour)),
        snem2000d;
        size=(1200, 700),
    )
end

