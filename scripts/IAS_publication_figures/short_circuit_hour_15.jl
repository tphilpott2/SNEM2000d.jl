snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots


# rms results dir
rms_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "rms_short_circuit",
)

# read results
rms_results = OrderedDict(
    150 => parse_pf_rms(rms_results_dir, "short_circuit_branch_782_tc_150ms"),
    310 => parse_pf_rms(rms_results_dir, "short_circuit_branch_782_tc_310ms"),
    320 => parse_pf_rms(rms_results_dir, "short_circuit_branch_782_tc_320ms"),
)

##
#########################################################################
# Plot rotor angle of gen 3301
#########################################################################

traces = AbstractTrace[]

# linestyles for each case
rotor_angle_linestyles = Dict(
    150 => "solid",
    310 => "dash",
    320 => "dot",
)

# make traces
for (tc, df) in rms_results
    push!(
        traces,
        PlotlyJS.scatter(
            x=df.time,
            y=df[:, "gen_3301_1_fipol"],
            name="$(tc/1000) s",
            line=attr(
                dash=rotor_angle_linestyles[tc],
                width=default_linewidth,
            ),
        ),
    )
end

# make plot
pl_rotor_angle = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_rotor_angle,
    yaxis=attr(
        range=[-190, 190],
        tickvals=[-180, -90, 0, 90, 180],
        ticktext=["180", "90", "0", "90", "180"],
        title="Rotor angle (deg)",
    ),
    xaxis=attr(
        range=[0, 4],
        title="Time (s)",
    ),
    legend=attr(
        title_text="Clearance time",
    ),
)

# export
display(pl_rotor_angle)
PlotlyJS.savefig(
    pl_rotor_angle,
    joinpath(figs_dir, "short_circuit_branch_782.png"),
    width=x_size,
    height=600,
    scale=3.0
)

##
#########################################################################
# Plot generator power for hour 310
#########################################################################

# extract results
df = rms_results[310]

# make traces
traces = AbstractTrace[
    PlotlyJS.scatter(
        x=df.time,
        y=df[:, "gen_3301_1_Psum_bus1"],
        name="Gen 3301",
        line=attr(width=default_linewidth),
    ),
    PlotlyJS.scatter(
        x=df.time,
        y=df[:, "wtg_Q4_1_Psum_bus1"],
        name="WTG Q4",
        line=attr(dash="dash", width=default_linewidth),
    ),
    PlotlyJS.scatter(
        x=df.time,
        y=df[:, "pv_Q4_1_Psum_bus1"],
        name="PV Q4",
        line=attr(dash="dashdot", width=default_linewidth),
    ),
    PlotlyJS.scatter(
        x=df.time,
        y=df[:, "gen_3559_1_Psum_bus1"],
        name="Gen 3559",
        line=attr(dash="dot", width=default_linewidth),
    ),
]

# make plot
pl_gen_power = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_gen_power,
    yaxis=attr(
        title="Active power (MW)",
    ),
    xaxis=attr(
        title="Time (s)",
        range=[0, 1]
    ),
)

# export
display(pl_gen_power)
PlotlyJS.savefig(
    pl_gen_power,
    joinpath(figs_dir, "short_circuit_branch_782_power.png"),
    width=x_size,
    height=600,
    scale=3.0
)

