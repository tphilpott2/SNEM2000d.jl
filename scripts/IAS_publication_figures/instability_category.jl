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
include(joinpath(snem2000d_dir, "scripts", "IAS_publication_figures", "common_plotting.jl"))
unstable_osc_plots_dir = joinpath(snem2000d_dir, "results", "mainland_lccs_plots", "manual_sort", "unstable")
path_res_summary = joinpath(snem2000d_dir, "results", "powerfactory", "mainland_lccs_results_summary.csv")

# load nem model
snem_2000d = get_snem_2000d()
# gen_data = get_gen_data_snem2000d(snem2000d)


# load results
df_res = CSV.File(path_res_summary) |> DataFrame
add_stability_category!(df_res, unstable_osc_plots_dir=unstable_osc_plots_dir)
add_ibg_penetration!(df_res) # add ibg penetration


# definitions of plot attributes for each category
categories = OrderedDict(
    "Crashed" => Dict(
        "data" => filter(r -> r.stability_category == "Crashed", df_res),
        "color" => :red,
        "markershape" => :diamond,
        "markerstrokewidth" => 0,
        "markersize" => 6,
    ),
    "Unstable" => Dict(
        "data" => filter(r -> r.stability_category == "Unstable", df_res),
        "color" => :blue,
        "markershape" => :hexagon,
        "markerstrokewidth" => 0,
        "markersize" => 6,
    ),
    "Stable" => Dict(
        "data" => filter(r -> r.stability_category == "Stable", df_res),
        "color" => :green,
        "markershape" => :xcross,
        "markerstrokewidth" => 1,
        "markersize" => 6,
    ),
)

# make plot
theme(:default)
pl_data = Plots.plot(
    # title="Disturbance Size vs IBG Penetration",
    ; xlabel="IBG Penetration [%]",
    ylabel="Disturbance Size [GW]",
    label=false,
    grid=false,
    gridalpha=0.3,
    framestyle=:axes,
    margin=(10, :mm),
    size=(1200, 600),
    legend=(0.1, 0.95),
    fontfamily="Times Roman",
    xtickfontsize=15,
    ytickfontsize=15,
    xlabelfontsize=20,
    ylabelfontsize=20,
    legendfontsize=18,
    # background_color=:gray,
)
for (category, data) in categories
    df = data["data"]
    Plots.scatter!(
        pl_data,
        df.ibg_penetration,
        df.disturbance_size ./ 1000,
        c=data["color"],
        markersize=data["markersize"],
        markerstrokewidth=data["markerstrokewidth"],
        marker=data["markershape"],
        alpha=0.7,
        label=category,
    )
end

# save
display(pl_data)
Plots.savefig(
    pl_data,
    joinpath(figs_dir, "instability_category.png"),
)
