snem2000d_dir = (@__DIR__) |> dirname |> dirname
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))
include(joinpath(@__DIR__, "common_plotting.jl")) # common parameters for plots

# define scenario and year
scenario = "2022 ISP Step Change"
year = 2050

# load opf_data
opf_data = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)

# parse results
results_dir = joinpath(
    snem2000d_dir,
    "results",
    "opf",
    string(year),
    "stage_2",
)
yearly_results = import_yearly_opf_results(results_dir)

##
#########################################################################
# Plot generation mix
#########################################################################

# read data
nem_pg_trace = get_trace_gen_pg(yearly_results, opf_data)
filter!(row -> row.area != 5, nem_pg_trace) # filter for mainland NEM

# prepare plotting data
x_series = get_trace_hour_range(nem_pg_trace)
hours = get_trace_hours(nem_pg_trace)
traces = AbstractTrace[]

# define colours for each generation type
gen_type_colours = Dict(
    "Thermal" => "black",
    "Hydro" => "blue",
    "Wind" => "green",
    "Solar" => "orange",
)

# define linestyle for each generation type
gen_type_linestyles = Dict(
    "Thermal" => "solid",
    "Hydro" => "dashdot",
    "Wind" => "dash",
    "Solar" => "dot",
)

# make traces for each generation type
for type in unique(nem_pg_trace.type)
    type_gen_p = filter(row -> row.type == type, eachrow(nem_pg_trace)) |> DataFrame
    y_series = size(type_gen_p, 1) == 0 ? zeros(length(hours)) : [
        sum(type_gen_p[:, hour]) for hour in hours
    ]
    push!(traces, PlotlyJS.scatter(
        x=x_series,
        y=y_series ./ 1000,
        name=type,
        line=attr(
            color=gen_type_colours[type],
            dash=gen_type_linestyles[type],
            width=default_linewidth,
        )
    ))
end

# make plot
pl_gen_dispatch = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)

# relayout with plot specific parameters
relayout!(
    pl_gen_dispatch,
    xaxis=attr(title="Half-hourly interval", showgrid=false),
    yaxis=attr(title="Active Power Generation (GW)", showgrid=false),
    showlegend=true,
    width=x_size,
    height=750
)

display(pl_gen_dispatch)
PlotlyJS.savefig(
    pl_gen_dispatch,
    joinpath(figs_dir, "scenarios_gen_dispatch.png"),
    width=x_size,
    height=600,
    scale=3.0
)

##
#########################################################################
# Plot renewable penetration
#########################################################################

# reload nem_pg_trace
nem_pg_trace = get_trace_gen_pg(yearly_results, opf_data)
filter!(row -> row.area != 5, nem_pg_trace) # filter for mainland NEM

# prepare plotting data
x_series = get_trace_hour_range(nem_pg_trace)
hours = get_trace_hours(nem_pg_trace)
traces = AbstractTrace[]

# make dataframe with generation by type
gen_df = DataFrame(:hour => hours)
for type in unique(nem_pg_trace.type)
    type_gen_p = filter(row -> row.type == type, eachrow(nem_pg_trace)) |> DataFrame
    gen_type_trace = size(type_gen_p, 1) == 0 ? zeros(length(hours)) : [
        sum(type_gen_p[:, hour]) for hour in hours
    ]
    gen_df[!, type] = gen_type_trace
end

# calculate IBG penetration
gen_df.total_generation = gen_df.Thermal + gen_df.Hydro + gen_df.Wind + gen_df.Solar
gen_df.IBG_penetration = 100 .* (gen_df.Wind + gen_df.Solar) ./ gen_df.total_generation

# make traces
traces = [
    PlotlyJS.scatter(
        x=x_series,
        y=gen_df.IBG_penetration,
        line=attr(
            width=default_linewidth,
        )
    ),
]

# make plot
pl_renewable_penetration = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_renewable_penetration,
    xaxis=attr(title="Half-hourly interval", showgrid=false),
    yaxis=attr(title="Renewable Penetration (%)", showgrid=false),
    width=x_size,
    height=600
)

# export
display(pl_renewable_penetration)
PlotlyJS.savefig(
    pl_renewable_penetration,
    joinpath(figs_dir, "scenarios_ibg_penetration.png"),
    width=x_size,
    height=600,
    scale=3.0
)

##
#########################################################################
# Plot demand
#########################################################################

# load demand trace
load_pd_trace = get_trace_load_pd(yearly_results, opf_data)

# prepare plotting data
x_series = get_trace_hour_range(load_pd_trace)
hours = get_trace_hours(load_pd_trace)

# make total load series
y_series = [sum(load_pd_trace[:, hour]) for hour in hours] ./ 1000

# make plot
pl_demand = PlotlyJS.plot(
    [PlotlyJS.scatter(x=x_series, y=y_series, name="Demand", line=attr(width=default_linewidth))],
    deepcopy(default_layout)
)

relayout!(
    pl_demand,
    xaxis=attr(title="Half-hourly interval", showgrid=false),
    yaxis=attr(title="Demand (GW)", showgrid=false),
    width=x_size,
    height=600
)
display(pl_demand)
PlotlyJS.savefig(
    pl_demand,
    joinpath(figs_dir, "scenarios_demand.png"),
    width=x_size,
    height=600,
    scale=3.0
)

##
#########################################################################
# Plot IBG penetration wit voltage sources
#########################################################################

# load trace
nem_pg_trace = get_trace_gen_pg(yearly_results, opf_data)

# full IBG
function get_gen_totals(nem_pg_trace)
    # make dataframe with generation by type
    hours = get_trace_hours(nem_pg_trace)
    gen_df = DataFrame(:hour => hours)
    for type in unique(nem_pg_trace.type)
        type_gen_p = filter(row -> row.type == type, eachrow(nem_pg_trace)) |> DataFrame
        gen_type_trace = size(type_gen_p, 1) == 0 ? zeros(length(hours)) : [
            sum(type_gen_p[:, hour]) for hour in hours
        ]
        gen_df[!, type] = gen_type_trace
    end

    gen_df.Total = zeros(length(hours))
    for type in unique(nem_pg_trace.type)
        gen_df.Total .+= gen_df[!, type]
    end

    gen_df.IBG_penetration = 100 .* (gen_df.Solar + gen_df.Wind) ./ gen_df.Total
    return gen_df
end
full_ibgs = get_gen_totals(nem_pg_trace)

# rez IBG voltage source
voltage_source_ibg_names = [
    "pv_N3_1",
    "wtg_N5_1",
    "wtg_V3_1",
    "wtg_V4_1",
    "pv_Q8_1",
    "wtg_Q8_1",
    "wtg_Q9_1",
    "wtg_S1_1",
    "wtg_S3_1",
]
for row in eachrow(nem_pg_trace)
    if row.name in voltage_source_ibg_names
        row.type = "Voltage_Source"
    elseif startswith(row.name, "pv")
        row.type = "Wind"
    elseif startswith(row.name, "wtg")
        row.type = "Solar"
    end
end
voltage_source_ibgs = get_gen_totals(nem_pg_trace)


# prepare plotting data
x_series = get_trace_hour_range(nem_pg_trace)
hours = get_trace_hours(nem_pg_trace)
traces = AbstractTrace[]

# make traces
traces = [
    PlotlyJS.scatter(
        x=x_series,
        y=full_ibgs.IBG_penetration,
        name="Full IBG Models",
        line=attr(width=default_linewidth),
    ),
    PlotlyJS.scatter(
        x=x_series,
        y=voltage_source_ibgs.IBG_penetration,
        name="Select Voltage <br> Source IBGs",
        line=attr(dash="dash", width=default_linewidth),
    ),
]

# make plot
pl_renewable_penetration = PlotlyJS.plot(
    traces,
    deepcopy(default_layout)
)
relayout!(
    pl_renewable_penetration,
    xaxis=attr(
        title="Half-hourly interval",
        showgrid=false,
    ),
    yaxis=attr(
        title="IBG Penetration (%)",
        showgrid=false,
    ),
    showlegend=true,
    width=x_size,
    height=700,
)

# export
display(pl_renewable_penetration)
PlotlyJS.savefig(
    pl_renewable_penetration,
    joinpath(figs_dir, "renewable_penetration_rez_IBGs.png"),
    width=x_size,
    height=600,
    scale=3.0,
)
