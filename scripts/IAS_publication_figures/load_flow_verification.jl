snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots

# define scenario and year
scenario = "2022 ISP Step Change"
year = 2050
hour = 1

# load network
snem2000d = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)

# make plot
pl_ldf = plot_bus_voltage_comparison(
    joinpath(snem2000d_dir, "results", "load_flow_verification", "hour_$(lpad(hour, 3, '0'))"),
    joinpath(snem2000d_dir, "results", "opf", "2050", "stage_2", string(hour)),
    snem2000d;
    return_plot=true,
    bottom_margin=(10, :mm),
    left_margin=(10, :mm),
    size=(x_size, 720),
    markersize=6,
    grid=false,
    common_kwargs...,
)

# export
display(pl_ldf)
Plots.savefig(pl_ldf, joinpath(figs_dir, "load_flow_verification.png"))

