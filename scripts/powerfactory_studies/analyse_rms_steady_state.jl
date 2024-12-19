snem2000d_dir = (@__DIR__) |> dirname |> dirname
# steady state rms results dir
rms_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "rms_steady_state"
)
cases = [replace(fp, ".csv" => "") for fp in readdir(rms_results_dir) if !startswith(fp, "header")]

##
############################################################
# Make speed plots and export to .png
# Plots are sorted manually from the target folders into stable/unstable or other categories of interest
############################################################

# directories
mainland_fig_dir = joinpath(snem2000d_dir, "results", "powerfactory", "rms_steady_state_plots", "mainland", "all")
tasmania_fig_dir = joinpath(snem2000d_dir, "results", "powerfactory", "rms_steady_state_plots", "tasmania", "all")

# make plots
for hour in cases
    # read data
    df = parse_pf_rms(rms_results_dir, hour)

    # define generator speed variable
    mainland_speed_vars = [name for name in names(df) if endswith(name, "speed") && !startswith(name, "gen_5")]
    tasmania_speed_vars = [name for name in names(df) if endswith(name, "speed") && startswith(name, "gen_5")]

    # mainland plot
    col_map = Dict(
        '1' => :red,
        '2' => :blue,
        '3' => :green,
        '4' => :orange,
    )
    # plot speed
    pl_mainland = Plots.plot(title="Speed - $hour", legend=false, size=(1550, 730))
    for var in mainland_speed_vars
        plot_pf!(df, var; c=col_map[var[5]])
    end
    Plots.savefig(pl_mainland, joinpath(mainland_fig_dir, "$hour.png"))

    # tasmania plot
    pl_tas = Plots.plot(title="Speed - $hour", legend=false, size=(1550, 730))
    for var in tasmania_speed_vars
        plot_pf!(df, var)
    end
    Plots.savefig(pl_tas, joinpath(tasmania_fig_dir, "$hour.png"))
end
