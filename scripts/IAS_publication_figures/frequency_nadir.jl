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

# get data required for fcas surplus
# include(joinpath(snem2000d_dir, "scripts", "powerfactory_studies", "lcc_studies", "analyse_FCAS_capacity.jl"))

# load results
df = CSV.File(path_res_summary) |> DataFrame
add_stability_category!(df, unstable_osc_plots_dir=unstable_osc_plots_dir)
filter!(r -> r.stability_category == "Stable", df)

# add extra columns to results
add_ibg_penetration!(df)
add_fcas_surplus!(df, fcas_data, hourly_fcas_data)
add_inertia!(df, snem_2000d)

# rename_columns
df.disturbance_size = df.disturbance_size ./ 1000
df.fcas_surplus = df.fcas_surplus ./ 1000
df.inertia = df.inertia ./ 1000
rename!(
    df,
    :ibg_penetration => "IBG Penetration (%)",
    :disturbance_size => "Disturbance Size (GW)",
    :nadir => "Nadir (Hz)",
    :fcas_surplus => "FCAS Surplus (GW)",
    :inertia => "Inertia (GWs)",
)

# make plots of nadir vs each parameter
theme(:default)
pls = Dict()
for param in [
    "IBG Penetration (%)",
    "FCAS Surplus (GW)",
    "Disturbance Size (GW)"
]
    pls[param] = Plots.scatter(
        df[!, param],
        df[!, "Nadir (Hz)"];
        xlabel=param,
        ylabel="Nadir (Hz)",
        legend=false,
        size=(1200, 500),
        markersize=4,
        markeralpha=0.7,
        markerstrokewidth=0,
        c=:blue,
        showgrid=true,
        gridalpha=0.8,
        gridlinewidth=0.5,
        gridcolor=:gray,
        ylims=(47, 50.15),
        margin=(8, :mm),
        # xlabelfontsize=20,
        tickfontsize=18,
        labelfontsize=24,
        fontfamily="Times Roman",
        frame=:box
        # xscale=:log10,
    )
    add_frequency_bands!(pls[param])
end

# save plots
for (param, plot) in pls
    Plots.savefig(plot, joinpath(figs_dir, "nadir_vs_$(join(split(param, " ")[1:end-1], " ")).png"))
    display(plot)
end


##
"""
Determine nadir band for each case and percentage of cases in each band.
"""

# rename!(df, "Nadir (Hz)" => :nadir)
insertcols!(df, 4, :nadir_band => fill("", size(df, 1)))
for row in eachrow(df)
    if row.nadir < 49
        row.nadir_band = "Extreme"
    elseif row.nadir < 49.75
        row.nadir_band = "Tolerance"
    elseif row.nadir < 49.85
        row.nadir_band = "Excursion"
    elseif row.nadir < 50.15
        row.nadir_band = "Normal"
    else
        throw(ArgumentError("Nadir band not found for $case_name"))
    end
end

clr()
temp_df = deepcopy(df)
function get_percentage(df, category)
    if isempty(df)
        return 0.0
    end
    return round(100 * count(r -> r.nadir_band == category, eachrow(df)) / size(df, 1), digits=2)
end

pfl()
println("Full res")
for category in unique(df.nadir_band)
    println("Percentage of $category cases: ", get_percentage(temp_df, category), "%")
end
