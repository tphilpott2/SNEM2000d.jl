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

# paths
path_res = joinpath(snem2000d_dir, "results", "powerfactory", "mainland_lccs_with_FCAS")
path_res_summary = joinpath(snem2000d_dir, "results", "powerfactory", "mainland_lccs_results_summary.csv")
plot_dir = joinpath(snem2000d_dir, "results", "mainland_lccs_plots", "manual_sort")
case_names = get_case_names(path_res)

# load nem model
snem_2000d = get_snem_2000d()
gen_data = get_gen_data_snem2000d(snem_2000d)

##
"""
generate results summary
"""

# generate results summary
(df_res, problem_cases) = process_time_series_results(
    path_res, gen_data;
)

CSV.write(path_res_summary, df_res)

##
"""
save figs of speed vs time for each case.
oscillatory instability is manually sorted from the plots.
"""

df = CSV.File(path_res_summary) |> DataFrame
insertcols!(df, 4, :stability_category => fill("", size(df, 1)))
for row in eachrow(df)
    if row.end_time != 20.0
        row.stability_category = "Crashed"
    elseif row.out_of_step || !row.δ_stab || row.overspeed || row.underspeed
        row.stability_category = "Unstable"
    else
        row.stability_category = "Stable"
    end
end
filter!(r -> r.stability_category == "Stable", df)

# get gen data and inertia dict
gen_data = get_gen_data_snem2000d(snem2000d)
inertia_dict = get_gen_inertia_dict(gen_data)

# make plots
for (idx, row) in enumerate(eachrow(df))
    case_name = get_case_name(row)
    println("$idx $case_name")
    pl = plot_speed(
        case_name,
        # title=i,
        title="$case_name",
        xlims=(0, 20),
    )
    hline!(pl, [50.5], c=:black, lw=3, ls=:dash, alpha=0.5)
    add_frequency_bands!(pl)
    Plots.savefig(pl, joinpath(plot_dir, "stable", "$case_name.png"))
end
