# file paths
snem2000d_dir = (@__DIR__) |> dirname |> dirname
dir_hypersim_csvs = joinpath(snem2000d_dir, "data", "hypersim_csvs")
custom_fuel_path = joinpath(snem2000d_dir, "data", "custom_fuels_and_costs.csv")
isphvdc_data_dir = joinpath(snem2000d_dir, "data", "ISPhvdc")

# load package
include(joinpath(snem2000d_dir, "src", "SNEM2000d.jl"))

# Select output directory
output_dir = joinpath(
    snem2000d_dir,
    "data",
    "SNEM2000d_pf_data",
)


# select scenario and year
scenario = "2022 ISP Step Change"
year = 2050

# load yearly data
snem2000d = prepare_opf_data_stage_2(scenario, year, snem2000d_dir)

# rename starbuses because of powerfactory name length limit
rename_starbuses!(snem2000d)

# assign names to converters
name_convs!(snem2000d)

# set convs to static gens
set_convs_to_static_gens!(snem2000d)

# set powerfactory model types based on powermodels NDD
set_powerfactory_model_types_from_powermodels!(snem2000d)
for (g, gen) in snem2000d["gen"] # update to use new WECC models
    if gen["powerfactory_model"] == "wind_generator"
        gen["powerfactory_model"] = "WECC_WTG_type_4A"
        gen["WECC_REEC"] = "REEC_A"
        gen["WECC_REGC"] = "REGC_B"
        gen["WECC_PlantControl"] = "REPC_A"
    elseif gen["powerfactory_model"] == "pv_generator"
        gen["powerfactory_model"] = "WECC_PV"
        gen["WECC_REEC"] = "REEC_A"
        gen["WECC_REGC"] = "REGC_B"
        gen["WECC_PlantControl"] = "REPC_A"
    end
end


# set all taps to 1.0. this makes conversion of shunts in powerfactory easier (but does make the base case unsolvable)
for (b, branch) in snem2000d["branch"]
    branch["tap"] = 1.0
end

# get xy coordinates from most recent bus_xy file
xy_dir = joinpath(snem2000d_dir, "data", "bus_xy")
bus_xy_file = joinpath(xy_dir, "bus_xy_v0$(length(readdir(xy_dir))).csv") # latest version
bus_xy = Dict(
    [
    row.name => (row.x, row.y)
    for row in eachrow(CSV.File(bus_xy_file) |> DataFrame)
]
)
for (b, bus) in snem2000d["bus"]
    bus["x"] = bus_xy[bus["name"]][1]
    bus["y"] = bus_xy[bus["name"]][2]
end

## Prepare output dfs
# creates output dfs on powermodels data
output_dfs = prepare_output_dfs(snem2000d, dir_hypersim_csvs)

# add powermodels index to description of all elements
add_descriptions!(output_dfs, snem2000d)

# configure tap changers
configure_tap_changers!(output_dfs, snem2000d)

# set branch shunt capacitors to be changable depending on the tap settings
set_variable_branch_shunts!(output_dfs, snem2000d)

# p.u. conversion of generator parameters to new mbase
convert_generator_parameters_to_new_mbase!(output_dfs, dir_hypersim_csvs)


# Set gens with zero rated power to 1e-6
fix_zero_rated_power_gens!(output_dfs)

# relax undervoltage/overvoltage triggers in WECC models
relax_REEC_A_voltage_triggers!(output_dfs)
# relax_REEC_B_voltage_triggers!(output_dfs)

# set convs to current sources
set_conv_model_type!(output_dfs, 1)

# relax Vr limits for avrs on gens 4033-4036
for row in eachrow(output_dfs["ElmDsl"]["IEEET1"])
    if row.elm_loc_name ∈ [
        "IEEET1_gen_4033_1",
        "IEEET1_gen_4034_1",
        "IEEET1_gen_4035_1",
        "IEEET1_gen_4036_1",
    ]
        row.elm_Vrmax = 10
    end
end

# set wtgs and pvs to voltage sources
output_dfs["ElmGenstat"].elm_iSimModel = [
    startswith(row.msc_powerfactory_model, "WECC") ? 2 : 0
    for row in eachrow(output_dfs["ElmGenstat"])
]

# set plant controllers to be off by default
output_dfs["ElmDsl"]["REPC_A"].elm_outserv = ones(Int64, size(output_dfs["ElmDsl"]["REPC_A"], 1))

# convert REPC_A to REPC_A_mod (active power control only)
output_dfs["ElmDsl"]["REPC_A_mod"] = select(output_dfs["ElmDsl"]["REPC_A"], [
    "elm_loc_name",
    "elm_Tp",
    "elm_FrqFlag",
    "elm_fdbd1",
    "elm_fdbd2",
    "elm_Ddn",
    "elm_Dup",
    "elm_Kpg",
    "elm_Kig",
    "elm_Tlag",
    "elm_femin",
    "elm_femax",
    "elm_Pmin",
    "elm_Pmax",
    "con_gen",
    "elm_outserv",
]) |> DataFrame
n_REPC = size(output_dfs["ElmDsl"]["REPC_A_mod"], 1)
output_dfs["ElmDsl"]["REPC_A_mod"].elm_Tp = fill(0.0, n_REPC)
output_dfs["ElmDsl"]["REPC_A_mod"].elm_Tlag = fill(0.0, n_REPC)
output_dfs["ElmDsl"]["REPC_A_mod"].elm_Kpg = fill(1.0, n_REPC)
output_dfs["ElmDsl"]["REPC_A_mod"].elm_Kig = fill(0.0, n_REPC)
delete!(output_dfs["ElmDsl"], "REPC_A")

# Parse graphical data and adds it to the output_dfs
add_graphic_data!(output_dfs, snem2000d)

## Export data
write_pf_data_csvs(output_dir, output_dfs)


