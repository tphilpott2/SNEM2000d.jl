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

# load network
snem2000d = prepare_opf_data_stage_2("2022 ISP Step Change", 2025, snem2000d_dir)
gen_colours_by_area = get_gen_colours_by_area(snem2000d)

# Read results from small signal round 1
small_signal_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "small_signal",
    "small_signal_1"
)

##
"""
Plots for mainland modes
"""

################## READ DATA ##################

case = "hour_001"

case_df = parse_powerfactory_small_signal(small_signal_results_dir, case)

# rename to remove underscores in variable ids
rename!(case_df, replace.(
    names(case_df),
    "x_lpf_d" => "xlpfd",
    "x_lpf_q" => "xlpfq",
))

# make mode dfs
mode_dfs = Dict()
for row in eachrow(case_df)
    mode_df = make_mode_df(row)
    mode_dfs[row.mode_index] = mode_df
end

##
################## Fast Mode ##########################
################## Left Eigenvector ##################
mode_df = deepcopy(mode_dfs[1])

# filter by threshold
filter!(row -> row["lEVec_mag"] > 0.1, mode_df)

# rename other gens in cluster
for row in eachrow(mode_df)
    if row.gen ∈ [
        "Gen 1039",
        "Gen 1040",
        "Gen 1041",
        "Gen 1042",
        "Gen 1043",
    ]
        row.gen = "Gens 1039-1043"
    end
end

theme(:default)
# create plot
max_mag = maximum(mode_df[!, "lEVec_mag"])
p = Plots.plot(
    size=(700, 600),
    # title="Left Eigenvector",
    legend=:topright,
    projection=:polar,
    showgrid=true,
    gridcolor=:black,
    gridstyle=:solid,
    gridalpha=0.4,
    lims=(0, max_mag),
    left_margin=(-400, :mm),
    ;
)


gdf = groupby(mode_df, :gen)

line_styles = Dict(
    "Gen 1038" => :dot,
    "WTG N3" => :dash,
    "Gens 1039-1043" => :solid,
)

gen_colours = Dict(
    "Gen 1038" => :steelblue,
    "WTG N3" => :salmon,
    "Gens 1039-1043" => :magenta,
)

for mode_df in gdf

    phi_vec = []
    mag_vec = []

    # add traces
    for row in eachrow(mode_df)
        # color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        append!(phi_vec, [0.0, rad(row["lEVec_phi"])])
        append!(mag_vec, [0.0, row["lEVec_mag"]])
    end

    Plots.plot!(
        p,
        phi_vec,
        mag_vec,
        label=mode_df.gen[1],
        color=gen_colours[mode_df.gen[1]],
        linewidth=2.0,
        linestyle=line_styles[mode_df.gen[1]],
        tickfontsize=12,
        legendfontsize=12,
        legendposition=(0.79, 0.98)
    )
end
display(p)

Plots.savefig(p, joinpath(figs_dir, "mode_1_left_eigenvector.png"))

##
################## Fast Mode ##########################
################## Right Eigenvector ##################
mode_df = deepcopy(mode_dfs[1])

# filter by var
filter!(row -> row["var"] == "phi", mode_df)

# normalise
mode_df[!, "rEVec_mag"] = mode_df[!, "rEVec_mag"] ./ maximum(mode_df[!, "rEVec_mag"])

# filter by threshold
filter!(row -> row["rEVec_mag"] > 0.1, mode_df)

# add areas
mode_df.areas = [gen_colours_by_area[row.gen] for row in eachrow(mode_df)]
colour_to_area = Dict(
    "blue" => "NSW",
    "red" => "QLD",
    "green" => "VIC",
)
mode_df.areas = [colour_to_area[row.areas] for row in eachrow(mode_df)]

gdf = groupby(mode_df, :areas)

# create plot
max_mag = maximum(mode_df[!, "rEVec_mag"])
p = Plots.plot(
    size=(700, 600),
    # title="Left Eigenvector",
    legend=:topright,
    projection=:polar,
    showgrid=true,
    gridcolor=:black,
    gridstyle=:solid,
    gridalpha=0.4,
    lims=(0, max_mag),
    left_margin=(-400, :mm),
    tickfontsize=12,
    legendfontsize=12,
    legendposition=(0.9, 0.98)
    ;
)

line_styles = Dict(
    "NSW" => :dash,
    "QLD" => :solid,
    "VIC" => :dashdot,
)

gen_colours = Dict(
    "NSW" => :steelblue,
    "QLD" => :salmon,
    "VIC" => :green,
)

for mode_df in gdf

    phi_vec = []
    mag_vec = []

    # add traces
    for row in eachrow(mode_df)
        # color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        append!(phi_vec, [0.0, rad(row["rEVec_phi"])])
        append!(mag_vec, [0.0, row["rEVec_mag"]])
    end

    Plots.plot!(
        p,
        phi_vec,
        mag_vec,
        label=mode_df.areas[1],
        color=gen_colours[mode_df.areas[1]],
        linewidth=2.5,
        linestyle=line_styles[mode_df.areas[1]],
    )
end
display(p)

Plots.savefig(p, joinpath(figs_dir, "mode_1_right_eigenvector.png"))
##
################## Slow Mode ##########################
################## Right Eigenvector ##################
mode_df = deepcopy(mode_dfs[3])

# filter by var
filter!(row -> row["var"] == "phi", mode_df)

# normalise
mode_df[!, "rEVec_mag"] = mode_df[!, "rEVec_mag"] ./ maximum(mode_df[!, "rEVec_mag"])

# filter by threshold
filter!(row -> row["rEVec_mag"] > 0.1, mode_df)

# add areas
mode_df.areas = [gen_colours_by_area[row.gen] for row in eachrow(mode_df)]
colour_to_area = Dict(
    "blue" => "NSW",
    "red" => "QLD",
    "green" => "VIC",
)
mode_df.areas = [colour_to_area[row.areas] for row in eachrow(mode_df)]

gdf = groupby(mode_df, :areas)

# create plot
max_mag = maximum(mode_df[!, "rEVec_mag"])
p = Plots.plot(
    size=(700, 600),
    # title="Left Eigenvector",
    legend=:topright,
    projection=:polar,
    showgrid=true,
    gridcolor=:black,
    gridstyle=:solid,
    gridalpha=0.4,
    lims=(0, max_mag),
    left_margin=(-400, :mm),
    tickfontsize=12,
    legendfontsize=12,
    legendposition=(0.9, 0.98)
    ;
)

line_styles = Dict(
    "NSW" => :dash,
    "QLD" => :solid,
    "VIC" => :dashdot,
)

gen_colours = Dict(
    "NSW" => :steelblue,
    "QLD" => :salmon,
    "VIC" => :green,
)

for mode_df in gdf

    phi_vec = []
    mag_vec = []

    # add traces
    for row in eachrow(mode_df)
        # color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        append!(phi_vec, [0.0, rad(row["rEVec_phi"])])
        append!(mag_vec, [0.0, row["rEVec_mag"]])
    end

    Plots.plot!(
        p,
        phi_vec,
        mag_vec,
        label=mode_df.areas[1],
        color=gen_colours[mode_df.areas[1]],
        linewidth=2.5,
        linestyle=line_styles[mode_df.areas[1]],
    )
end
display(p)

Plots.savefig(p, joinpath(figs_dir, "mode_2_right_eigenvector.png"))

##
"""
Plots for TAS modes
"""

################## READ DATA ##################
case = "hour_036"
case_df = parse_powerfactory_small_signal(small_signal_results_dir, case)
# rename to remove underscores in variable ids
rename!(case_df, replace.(
    names(case_df),
    "x_lpf_d" => "xlpfd",
    "x_lpf_q" => "xlpfq",
))
# make mode dfs
mode_dfs = Dict()
for row in eachrow(case_df)
    mode_df = make_mode_df(row)
    mode_dfs[row.mode_index] = mode_df
end

##
################## Fast Mode ##########################
################## Right Eigenvector ##################
mode_df = deepcopy(mode_dfs[1])

# filter by var
filter!(row -> row["var"] == "phi", mode_df)

# normalise
mode_df[!, "rEVec_mag"] = mode_df[!, "rEVec_mag"] ./ maximum(mode_df[!, "rEVec_mag"])

# filter by threshold
filter!(row -> row["rEVec_mag"] > 0.1, mode_df)

# Group generators
gen_group_colours = Dict(
    "Gen 5008" => "blue",
    "Gen 5010" => "blue",
    "Gen 5012" => "blue",
    "Gen 5030" => "blue",
    "Gen 5031" => "blue",
    "Gen 5231" => "blue",
    "Gen 5233" => "blue",
    "Gen 5036" => "blue",
    "Gen 5020" => "blue",
    "Gen 5230" => "blue",
    "Gen 5234" => "blue",
)
mode_df.colours = [haskey(gen_group_colours, row.gen) ? gen_group_colours[row.gen] : "blue" for row in eachrow(mode_df)]


# colour_to_area = Dict(
#     "blue" => "NSW",
#     "red" => "QLD",
#     "green" => "VIC",
#     "purple" => "TAS",
# )

# mode_df.areas = [colour_to_area[row.areas] for row in eachrow(mode_df)]

gdf = groupby(mode_df, :colours)


line_styles = Dict(
    "blue" => :solid,
    "red" => :dash,
    "purple" => :dashdot,
)

gen_colours = Dict(
    "blue" => :steelblue,
    "red" => :salmon,
    "purple" => :purple,
)

# create plot
max_mag = maximum(mode_df[!, "rEVec_mag"])
pl_5 = Plots.plot(
    size=(700, 600),
    # title="Left Eigenvector",
    legend=:topright,
    projection=:polar,
    showgrid=true,
    gridcolor=:black,
    gridstyle=:solid,
    gridalpha=0.4,
    lims=(0, max_mag),
    left_margin=(-400, :mm),
    tickfontsize=12,
    legendfontsize=12,
    legendposition=(0.9, 0.98)
    ;
)
for mode_df in gdf

    phi_vec = []
    mag_vec = []

    # add traces
    for row in eachrow(mode_df)
        # color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        append!(phi_vec, [0.0, rad(row["rEVec_phi"])])
        append!(mag_vec, [0.0, row["rEVec_mag"]])
    end

    Plots.plot!(
        pl_5,
        phi_vec,
        mag_vec,
        label="TAS",
        color=gen_colours[mode_df.colours[1]],
        linewidth=2.5,
        linestyle=line_styles[mode_df.colours[1]],
    )
end
display(pl_5)

Plots.savefig(pl_5, joinpath(figs_dir, "mode_5_right_eigenvector.png"))

##
################## Slow Mode ##########################
################## Right Eigenvector ##################
mode_df = deepcopy(mode_dfs[3])

# filter by var
filter!(row -> row["var"] == "phi", mode_df)

# normalise
mode_df[!, "rEVec_mag"] = mode_df[!, "rEVec_mag"] ./ maximum(mode_df[!, "rEVec_mag"])

# filter by threshold
filter!(row -> row["rEVec_mag"] > 0.1, mode_df)

# Group generators
gen_group_colours = Dict(
    "Gen 5008" => "blue",
    "Gen 5010" => "blue",
    "Gen 5012" => "blue",
    "Gen 5030" => "blue",
    "Gen 5031" => "blue",
    "Gen 5231" => "blue",
    "Gen 5233" => "blue",
    "Gen 5036" => "blue",
    "Gen 5020" => "blue",
    "Gen 5230" => "blue",
    "Gen 5234" => "blue",
)
mode_df.colours = [haskey(gen_group_colours, row.gen) ? gen_group_colours[row.gen] : "blue" for row in eachrow(mode_df)]


# colour_to_area = Dict(
#     "blue" => "NSW",
#     "red" => "QLD",
#     "green" => "VIC",
#     "purple" => "TAS",
# )

# mode_df.areas = [colour_to_area[row.areas] for row in eachrow(mode_df)]

gdf = groupby(mode_df, :colours)


line_styles = Dict(
    "blue" => :solid,
    "red" => :dash,
    "purple" => :dashdot,
)

gen_colours = Dict(
    "blue" => :steelblue,
    "red" => :salmon,
    "purple" => :purple,
)

# create plot
max_mag = maximum(mode_df[!, "rEVec_mag"])
pl_6 = Plots.plot(
    size=(700, 600),
    # title="Left Eigenvector",
    legend=:topright,
    projection=:polar,
    showgrid=true,
    gridcolor=:black,
    gridstyle=:solid,
    gridalpha=0.4,
    lims=(0, max_mag),
    left_margin=(-400, :mm),
    tickfontsize=12,
    legendfontsize=12,
    legendposition=(0.9, 0.98)
    ;
)
for mode_df in gdf

    phi_vec = []
    mag_vec = []

    # add traces
    for row in eachrow(mode_df)
        # color = haskey(gen_colours, row.gen) ? gen_colours[row.gen] : :black
        append!(phi_vec, [0.0, rad(row["rEVec_phi"])])
        append!(mag_vec, [0.0, row["rEVec_mag"]])
    end

    Plots.plot!(
        pl_6,
        phi_vec,
        mag_vec,
        label="TAS",
        color=gen_colours[mode_df.colours[1]],
        linewidth=2.5,
        linestyle=line_styles[mode_df.colours[1]],
    )
end
display(pl_6)

Plots.savefig(pl_6, joinpath(figs_dir, "mode_6_right_eigenvector.png"))

