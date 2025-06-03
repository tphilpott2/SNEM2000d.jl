function get_parent_dir(parent_dir::String, child_dir::String)
    println("searching for $parent_dir from $child_dir")
    dir_path = child_dir
    last_dir = dir_path
    while !endswith(dir_path, parent_dir)
        dir_path = dirname(dir_path)
        last_dir == dir_path && throw(ArgumentError("Package $parent_dir not found. last dir: $dir_path"))
        last_dir = dir_path
    end
    return dir_path
end
snem2000d_dir = get_parent_dir("SNEM2000d", @__DIR__)
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots


# get data from external script
# include(joinpath(snem2000d_dir, "scripts", "powerfactory_studies", "lcc_studies", "analyse_FCAS_capacity.jl"))
df = deepcopy(summary_df)
sort!(df, :hour)


pl = PlotlyJS.plot([
        PlotlyJS.scatter(
            x=df.hour,
            y=0.1 * (df.fcas_procured .+ df.sg_fcas),
            name="FCAS",
            line=attr(width=2)
        ),
        PlotlyJS.scatter(
            x=df.hour,
            y=0.1 * df.lcc_max,
            name="LCC",
            line=attr(width=2, dash="dash")
        )
    ],
    deepcopy(default_layout)
)

# relayout with plot specific parameters
relayout!(
    pl,
    xaxis=attr(title="Hour", showgrid=false),
    yaxis=attr(title="FCAS/LCC (GW)", showgrid=false),
    showlegend=true,
    width=x_size,
    height=750
)

display(pl)
PlotlyJS.savefig(
    pl,
    joinpath(figs_dir, "fcas_procured.png"),
    width=x_size,
    height=600,
    scale=3.0
)
