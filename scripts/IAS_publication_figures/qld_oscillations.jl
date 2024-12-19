snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots

#########################################################################
# Time domain plots of QLD oscillations
#########################################################################

# rms results dir
rms_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "rms_steady_state",
)

# make plot for hours 74, 115, 120
pls = Dict()
for hour in [
    "hour_074",
    "hour_115",
    "hour_120"
]
    # read data
    df = parse_pf_rms(rms_results_dir, hour)

    # qld generator speed vars
    qld_speed_vars = [
        name for name in names(df) if endswith(name, "speed") && startswith(name, "gen_3")
    ]

    # make plots
    traces = AbstractTrace[]
    for speed_var in qld_speed_vars
        push!(traces, PlotlyJS.scatter(
            x=df.time,
            y=df[!, speed_var],
            mode="lines",
        ))
    end
    pl = PlotlyJS.plot(
        traces,
        deepcopy(default_layout)
    )

    # modifications from default layout
    relayout!(pl,
        xaxis_title="Time (s)",
        yaxis_title="Speed (pu)",
        height=600,
        showlegend=false,
        xaxis_range=[0, 60],
    )

    # save plot
    pls[hour] = copy(pl)
end

# rescaling y axis
relayout!(
    pls["hour_120"],
    yaxis_range=[0.9935, 1.0055]
)

# export
for (hour, pl) in pls
    display(pl)
    PlotlyJS.savefig(
        pl,
        joinpath(figs_dir, "qld_oscillations_$(hour).png"),
        width=x_size,
        height=500,
        scale=3.0
    )
end



##
#########################################################################
# Eigenvalues of QLD oscillations
#########################################################################

ss_marker_size = 10
# get case list
qld_oscillation_intervals = replace.(readdir(joinpath(
        snem2000d_dir,
        "results",
        "powerfactory",
        "rms_steady_state_plots",
        "mainland",
        "qld_oscillations"
    )),
    ".png" => ""
)

# parse modes and dominant states from small signal results
result_df = get_small_signal_mode_summary(
    joinpath(
        snem2000d_dir,
        "results",
        "powerfactory",
        "small_signal"
    ),
    qld_oscillation_intervals
)

# make traces for plotting
traces = AbstractTrace[]

# modes dominated by PV Q9
pv_q9 = filter(row -> row.dominant_gen == "PV Q9", result_df) |> DataFrame
push!(traces, PlotlyJS.scatter(
    x=pv_q9.hour,
    y=pv_q9.real_part,
    mode="markers",
    marker=attr(color="red", size=ss_marker_size, symbol="cross"),
    name="PV Q9"
))

# modes dominated by gen_3301
gen_3301 = filter(row -> row.dominant_gen == "Gen 3301", result_df) |> DataFrame
push!(traces, PlotlyJS.scatter(
    x=gen_3301.hour,
    y=gen_3301.real_part,
    mode="markers",
    marker=attr(color="blue", size=ss_marker_size, symbol="x"),
    name="Gen 3301"
))

# make plot
pl_eigenvalues = PlotlyJS.plot(
    traces,
    deepcopy(default_layout),
)
relayout!(
    pl_eigenvalues,
    xaxis_title="Half-hourly interval",
    yaxis_title="Eigenvalue real parts",
    xaxis=attr(
        showgrid=false,
    ),
    yaxis=attr(
        showgrid=true,
        type="log",
        tickvals=[0, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0],
        ticktext=["0", "0.02", "0.05", "0.1", "0.2", "0.5", "1.0", "2.0", "5.0", "10.0", "20.0"],
        # range=[0, 2]
    ),
    legend=attr(
    # title_text="Dominant state",
    # bordercolor="black",
    # borderwidth=1,
    ),
)

# export
PlotlyJS.savefig(
    pl_eigenvalues,
    joinpath(figs_dir, "qld_oscillation_eigenvalues.png"),
    width=x_size,
    height=500,
    scale=3.0
)
display(pl_eigenvalues)
