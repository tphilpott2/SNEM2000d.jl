# # make directory if doesnt exist
# function mkdir_if(dir_path)
#     if isdir(dir_path) == false
#         mkdir(dir_path)
#         println("Created: '$dir_path'")
#     else
#         println("Already exists: '$dir_path'")
#     end
#     return dir_path
# end

##########################################################################
# Functions for converting dictionaries to dataframes
# Useful with PowerModels.jl NDD
##########################################################################

function dict_to_dataframe(data_dict::Dict, vars::Vector{Any})
    df = DataFrame()
    for var in vars
        if var == "k"
            df[!, "ind"] = [k for (k, v) in data_dict]
        elseif isa(var, Tuple)
            subdict_name = var[1]
            subdict_vars = var[2]
            for subdict_var in subdict_vars
                df[!, subdict_var] = [v[subdict_name][subdict_var] for (k, v) in data_dict]
            end
        else
            try
                df[!, var] = [v[var] for (k, v) in data_dict]
            catch
                println("Issue with parsing var: $var")
            end
        end
    end
    return df
end

function dict_to_dataframe(data_dict::Dict, vars::Vector{String}; add_missing_vars::Bool=false)
    df = DataFrame()
    for var in vars
        if var == "k"
            df[!, "ind"] = [k for (k, v) in data_dict]
        else
            if !add_missing_vars
                try
                    df[!, var] = [v[var] for (k, v) in data_dict]
                catch
                    println("Issue with parsing var: $var")
                end
            else
                df[!, var] = [var ∈ keys(v) ? v[var] : missing for (k, v) in data_dict]
            end
        end
    end
    return df
end

function dict_to_dataframe(data_dict::Dict, ; add_missing_vars::Bool=false)
    vars = ["k"]
    for v in values(data_dict)
        append!(vars, vec(keys(v)))
    end
    return dict_to_dataframe(data_dict, unique(vars), add_missing_vars=add_missing_vars)
end


##########################################################################
# Functions to handle PowerFactory results
##########################################################################

function parse_powerfactory_header(fp_header::String)
    df = DataFrame(
        :col => Vector{String}(undef, 0),
        :elm => Vector{String}(undef, 0),
        :var => Vector{String}(undef, 0),
    )

    open(fp_header) do file
        elm = "time"
        for (idx, line) in enumerate(eachline(file))
            idx <= 2 ? continue : nothing   # skip preamble
            if startswith(line, "\\") || startswith(line, "'") # get elm from elm data lines
                elm_with_class = split(line, "\\")[end]
                elm = split(elm_with_class, ".")[1]
            else
                cells = split(line, ",")[1:2]
                push!(df, [
                    cells[1],   # column
                    elm,
                    cells[2],   # var
                ])
            end
        end
    end

    return df
end
function parse_powerfactory_rms(fp::String, header_df::DataFrame; drop_missing::Bool=true)
    df = CSV.File(
        fp,
        header=1:2,
        select=header_df.col,
        missingstring=["nan", "-nan(ind)", "#INF", "-#INF"],
    ) |> DataFrame

    # process names
    header_df.var = [join(split(var, ":")[2:end], "_") for var in header_df.var] # remove variable set
    nms = ["$(row.elm)_$(row.var)" for row in eachrow(header_df)] # join elm and variable
    nms[1] = "time" # first column is time
    rename!(df, nms)

    # drop missing
    drop_missing && dropmissing!(df)
    return df
end

# parse pf rms with file name and folder path
function parse_powerfactory_rms(
    folder_path::String,
    file_name::String;
    elms::Vector{String}=String[],
    vars::Vector{String}=String[],
    drop_missing::Bool=true,
)
    # get header df
    fp_header = joinpath(folder_path, "header_$(file_name).csv")
    fp_file = joinpath(folder_path, "$(file_name).csv")
    header_df = parse_powerfactory_header(fp_header)


    # filter header_df for selected elms and vars
    if !isempty(elms)
        push!(elms, "time") # time is always included
        filter!(r -> r.elm in elms, header_df)
    end
    if !isempty(vars)
        push!(vars, "b:tnow") # b:tnow (time) is always included
        filter!(r -> r.var in vars, header_df)
    end
    header_df.col = parse.(Int, header_df.col) # convert column to int

    # parse rms file
    df = parse_powerfactory_rms(fp_file, header_df)
    return df
end

# plot_results
function plot_powerfactory(df::DataFrame, var::String; kwargs...)
    return plot(df.time, df[:, var], label=var, lw=2; kwargs...)
end
function plot_powerfactory(f::Function, df::DataFrame, var::String; kwargs...)
    return plot(df.time, f.(df[:, var]), label=var, lw=2; kwargs...)
end
function plot_powerfactory!(df::DataFrame, var::String; kwargs...)
    plot!(df.time, df[:, var], label=var, lw=2; kwargs...)
end
function plot_powerfactory!(f::Function, df::DataFrame, var::String; kwargs...)
    return plot!(df.time, f.(df[:, var]), label=var, lw=2; kwargs...)
end

# parse small signal data
function parse_powerfactory_small_signal(folder_path, file_name)
    if !endswith(file_name, ".csv")
        file_name *= ".csv"
    end
    data_df = CSV.File(joinpath(folder_path, file_name), header=1:2) |> DataFrame
    header_df = CSV.File(joinpath(folder_path, "header_$(file_name)")) |> DataFrame
    rename!(header_df, [:state, :var])
    dropmissing!(header_df, :var)


    gen_names = [split(name, ", ")[1] for name in names(data_df)]
    elm_names = [
        replace(
            name,
            "_Observability" => "",
            "_Controllability" => "",
            "_Participation" => "",
        )
        for name in gen_names]

    for row in eachrow(header_df)
        state_split = split(row.state, ",")
        i = parse(Int, state_split[1])
        state_name = state_split[2]
        var = split(row.var, ",")[1]
        elm_names[i] = "$(elm_names[i])_$(state_name)_$(var)"
    end
    elm_names[1] = "mode_index"
    elm_names[2] = "real_part"
    elm_names[3] = "imag_part"

    rename!(data_df, elm_names)
    return data_df
end

##########################################################################
# Functions to select columns from a dataframe
##########################################################################

function select_df_cols!(DF, search_term::String)
    nms = [nm for nm in names(DF) if occursin(search_term, nm)]
    select!(DF, nms)
    return DF
end

function select_df_cols!(DF, search_terms::Vector{String})
    nms = [nm for nm in names(DF) if any(occursin(search_term, nm) for search_term in search_terms)]
    select!(DF, nms)
    return DF
end

function select_df_cols!(DF, search_terms::Vector{Any})
    saved_inds = [x for x in search_terms if typeof(x) == Int64]
    search_terms = [x for x in search_terms if typeof(x) == String]
    searched_inds = [idx for (idx, nm) in enumerate(names(DF)) if any(occursin(search_term, nm) for search_term in search_terms)]
    inds = sort!(unique(append!(saved_inds, searched_inds)))
    select!(DF, inds)
    return DF
end

function select_df_cols(DF::DataFrame, search_terms)
    temp_df = copy(DF)
    select_df_cols!(temp_df, search_terms)
    return temp_df
end