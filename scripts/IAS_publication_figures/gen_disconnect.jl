snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots

# results dir
results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "rms_gen_disconnect",
)

# read results
rms_results = parse_pf_rms(results_dir, "gen_disconnect_gen_3301_1")

##
#########################################################################
# make plot of generator speed
#########################################################################

# extract data
df = deepcopy(rms_results)
select_df_cols!(df, [1, "speed"])

# make speed traces
traces = AbstractTrace[]
for (col_name, col_data) in pairs(eachcol(df))
    col_name == :time && continue
    col_name == :gen_3301_1_speed && continue # skip faulted generator
    push!(traces, PlotlyJS.scatter(
        x=df.time,
        y=col_data,
        # name=col_name,
        line=attr(width=default_linewidth),
    ))
end

# make plot
pl_speed = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_speed,
    showlegend=false,
    xaxis_title="Time (s)",
    yaxis_title="Speed (pu)",
    height=500,
    width=x_size,
)

# export
display(pl_speed)
PlotlyJS.savefig(
    pl_speed,
    joinpath(figs_dir, "gen_disconnect_speed.png"),
    width=x_size,
    height=500,
    scale=3.0,
)

##
#########################################################################
# make plot of generator power
#########################################################################

# extract data
df = deepcopy(rms_results)

# traces
traces = AbstractTrace[
    PlotlyJS.scatter(
        x=df.time,
        y=df.pv_Q8_1_Psum_bus1 .- df.pv_Q8_1_Psum_bus1[1],
        name="PV Q8",
        line=attr(width=default_linewidth, dash="dash"),
    ),
    PlotlyJS.scatter(
        x=df.time,
        y=df.wtg_Q9_1_Psum_bus1 .- df.wtg_Q9_1_Psum_bus1[1],
        name="WTG Q9",
        line=attr(width=default_linewidth),
    )
]

# make plot
pl_power = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_power,
    xaxis_title="Time (s)",
    yaxis_title="Active Power (MW)",
    height=500,
    width=x_size,
)

# export
display(pl_power)
PlotlyJS.savefig(
    pl_power,
    joinpath(figs_dir, "gen_disconnect_power.png"),
    width=x_size,
    height=500,
    scale=3.0,
)

