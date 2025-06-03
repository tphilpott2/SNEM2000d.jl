snem2000d_dir = (@__DIR__) |> dirname |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

# dataframe to latex table
function dataframe_to_latex(
    df;
    centering=true,
    caption=false,
    label=false,
    borders=false,
    environment="table",
    copy=true,
    location="h"
)
    latex = "\\begin{$(environment)}[$(location)]\n"

    indent = "\t"
    if caption !== false
        latex *= "$indent\\caption{$(caption)}\n"
    end
    if label !== false
        latex *= "$indent\\label{$(label)}\n"
    end
    if centering
        latex *= "$indent\\centering\n"
    end

    # Add vertical borders if enabled
    if borders
        latex *= "$indent\\begin{tabular}{|" * repeat("c|", size(df, 2)) * "}\n"
    else
        latex *= "$indent\\begin{tabular}{" * repeat("c", size(df, 2)) * "}\n"
    end

    indent *= "\t"
    # Add top horizontal border if enabled
    if borders
        latex *= "$indent\\hline\n"
    end

    # Add header
    header = join(names(df), " & ")
    latex *= "$indent$header \\\\\n"

    # Add header border
    if borders
        latex *= "$indent\\hline\n"
    end

    # Add data rows
    for row in eachrow(df)
        # Add row border if enabled
        latex *= "$indent"
        if borders
            latex *= join(row, " & ") * " \\\\\\hline\n"
        else
            latex *= join(row, " & ") * " \\\\\n"
        end
    end

    # End table
    indent = "\t"
    latex *= "$indent\\end{tabular}"
    indent = ""
    latex *= "\n$indent\\end{$(environment)}"

    # copy to clipboard
    copy && clipboard(latex)
    return latex
end

##
"""
# Read all small signal results, calculate mode summary and make mode dfs
"""

# load network
# snem2000d = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)

# Read results from small signal round 1
small_signal_results_dir = joinpath(
    snem2000d_dir,
    "results",
    "powerfactory",
    "small_signal",
    "small_signal_1"
)
cases = [replace(fp, ".csv" => "") for fp in readdir(small_signal_results_dir) if !startswith(fp, "header")]
# mode_summary_df = get_small_signal_mode_summary(small_signal_results_dir, cases)

gdf = groupby(mode_summary_df, :dominant_gen)

mode_dfs = Dict()

# process each case
for case in cases
    case_df = parse_powerfactory_small_signal(small_signal_results_dir, case)

    # rename to remove underscores in variable ids
    rename!(case_df, replace.(
        names(case_df),
        "x_lpf_d" => "xlpfd",
        "x_lpf_q" => "xlpfq",
    ))
    # # remove one of the complex parts
    # filter!(row -> row.imag_part >= 0.0, case_df)

    # make mode dfs
    mode_dfs[case] = Dict()
    for row in eachrow(case_df)
        mode_df = make_mode_df(row)
        mode_dfs[case][row.mode_index] = mode_df
    end
    println("Processed case $case")
end

##
"""
Write unstable hours for each generator group to a text file (stage 1 only)
"""

fp_unstable_hours = joinpath(snem2000d_dir, "results", "powerfactory", "small_signal", "unstable_hours_stage_1.txt")
# Write unique hours for each generator group to a text file
open(fp_unstable_hours, "w") do f
    for (key, group) in pairs(gdf)
        println(f, "$(key.dominant_gen): $(sort!(unique(group.hour)))")
    end
end

##
"""
Make table with summary of unstable modes (stage 1 only)
"""

# Create a copy of the mode summary dataframe for classification
classification_df = deepcopy(mode_summary_df)

# Filter out negative imaginary parts to avoid duplicate modes
filter!(row -> row.imag_part >= 0.0, classification_df)

# Sort by dominant generator and imaginary part
sort!(classification_df, ["dominant_gen", "imag_part"], rev=[false, true])

# Initialize classification column
classification_df.classification = classification_df.dominant_gen

# Classify modes based on generator and frequency
for row in eachrow(classification_df)
    if row.dominant_gen == "Gen 1038" && isapprox(abs(row.imag_part), 1.0, atol=0.2)
        row.classification = "Gen 1038 Fast"
    elseif row.dominant_gen == "Gen 1038" && isapprox(abs(row.imag_part), 0.1, atol=0.1)
        row.classification = "Gen 1038 Slow"
    end
end

# Group by classification for analysis
gdf_classification = groupby(classification_df, :classification)

# Calculate damping ratio and frequency for each mode
for g in gdf_classification
    g.damping_ratio = [-row.real_part / abs(row.real_part + row.imag_part) for row in eachrow(g)]
    g.frequency = [row.imag_part / (2π) for row in eachrow(g)]
end

# Combine results into summary statistics
output_df = combine(
    gdf_classification,
    "damping_ratio" => minimum => "min_damping_ratio",
    "damping_ratio" => maximum => "max_damping_ratio",
    "frequency" => minimum => "min_frequency",
    "frequency" => maximum => "max_frequency",
    "hour" => (x -> length(x)) => "num_hours",
)

# Round numerical columns for presentation
for col_name in ["min_damping_ratio", "max_damping_ratio", "min_frequency", "max_frequency"]
    output_df[!, col_name] = round.(output_df[!, col_name], digits=4)
end

# Add area classification based on generator number
output_df.area = [
    startswith(row.classification, "Gen 1") ? "Mainland" : "Tasmania" for row in eachrow(output_df)
]

# Sort by area and number of hours observed
sort!(output_df, [:area, :num_hours], rev=[false, true])

# Add index column
output_df.index = vec(1:size(output_df, 1))

# Select and rename columns for final presentation
select!(output_df,
    :index,
    :area,
    :num_hours,
    :min_damping_ratio,
    :max_damping_ratio,
    :min_frequency,
    :max_frequency,
)

rename!(output_df,
    :min_damping_ratio => "Minimum Damping Ratio",
    :max_damping_ratio => "Maximum Damping Ratio",
    :min_frequency => "Minimum Frequency",
    :max_frequency => "Maximum Frequency",
    :num_hours => "Number of Observed Intervals",
    :area => "Area",
    :index => "Index",
)

# Export to LaTeX table format
dataframe_to_latex(
    output_df,
    copy=false,
    caption="Small Signal Mode Analysis",
    label="small_signal_mode_analysis",
    borders=true,
    environment="table*",
) |> clipboard

