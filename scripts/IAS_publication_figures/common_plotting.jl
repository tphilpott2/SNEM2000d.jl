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
# define figures directory
figs_dir = joinpath(snem2000d_dir, "results", "IAS_publication_figures")


# common kwargs for consistent plotting style
x_size = 1500
common_kwargs = [
    :framestyle => :box,
    :fontfamily => "Times Roman",
    :xtickfontsize => 25,
    :ytickfontsize => 25,
    :xlabelfontsize => 30,
    :ylabelfontsize => 30,
    :legendfontsize => 30,
]

# plotlyjs common kwargs
plotlyjs_margin = attr(b=80, l=80)

plotlyjs_xgrid = attr(
    showgrid=true,
    gridcolor="white",
    gridwidth=1,
    showline=true,
    linewidth=1,
    linecolor="black",
)

plotlyjs_ygrid = attr(
    showgrid=true,
    gridcolor="white",
    gridwidth=1,
    showline=true,
    linewidth=1,
    linecolor="black",
)

plotlyjs_plot_bgcolor = "white"
plotlyjs_paper_bgcolor = "white"

plotlyjs_font = attr(
    family="Times Roman",
    size=36
)

default_layout = Layout(
    width=x_size,
    height=900,
    margin=plotlyjs_margin,
    plot_bgcolor=plotlyjs_plot_bgcolor,
    paper_bgcolor=plotlyjs_paper_bgcolor,
    xaxis=plotlyjs_xgrid,
    yaxis=plotlyjs_ygrid,
    font=plotlyjs_font,
)

default_linewidth = 3
