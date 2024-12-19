snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots


# rms results dir
rms_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "rms_steady_state",
)

# hour to plot
hour = "046"

# load results
df = parse_pf_rms(rms_results_dir, "hour_$hour")

# get mainland gen speed vars
speed_vars = [name for name in names(df) if endswith(name, "speed")]
mainland_gens = [name for name in speed_vars if !startswith(name, "gen_5")]

# make traces
traces = AbstractTrace[]
for speed_var in mainland_gens
    push!(
        traces,
        PlotlyJS.scatter(
            x=df.time,
            y=df[!, speed_var],
            mode="lines",
            showlegend=false,
            line=attr(width=default_linewidth),
        )
    )
end

# make plot
pl_gen_speed = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_gen_speed,
    xaxis_title="Time (s)",
    yaxis_title="Speed (pu)",
    width=x_size,
    height=900,
)

# export plot
display(pl_gen_speed)
PlotlyJS.savefig(
    pl_gen_speed,
    joinpath(figs_dir, "unstable_mainland_gens_hour_$(hour).png"),
    width=x_size,
    height=600,
    scale=3.0
)
