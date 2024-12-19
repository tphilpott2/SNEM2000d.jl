# define figures directory
snem2000d_dir = (@__DIR__) |> dirname |> dirname
figs_dir = joinpath(snem2000d_dir, "results", "IAS_publication_figures")

# common kwargs for consistent plotting style
x_size = 1500
common_kwargs = [
    :framestyle => :box,
    :fontfamily => "Times Roman",
    :xtickfontsize => 22,
    :ytickfontsize => 22,
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
    size=24
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
