###############################################################
# Functions to modify the PowerModels NDD data before exporting to PowerFactory
###############################################################

# rename starbuses from "starbus_xf_XXXX_XXXX_XXXX_X" to "sb_XXXX_XXXX_XXXX_X"
# this is done because of name length restrictions in powerfactory
# rename buses from connection XX to bus_XX for consistency
function rename_starbuses!(data)
    for (b, bus) in data["bus"]
        bus_name = bus["name"]
        bus["name"] = replace(bus_name, "starbus_xf_" => "sb_")
        bus["name"] = replace(bus["name"], "connection " => "bus_")
        if bus_name != bus["name"]
            println("Renamed bus: $bus_name -> $(bus["name"])")
        end
    end
end

# assigns names to converters
function name_convs!(data)
    data["convdc"]["1"]["name"] = "conv_BASSLINK_VIC"
    data["convdc"]["2"]["name"] = "conv_BASSLINK_TAS"
    data["convdc"]["3"]["name"] = "conv_TERRANORA_NSW"
    data["convdc"]["4"]["name"] = "conv_TERRANORA_QLD"
    data["convdc"]["5"]["name"] = "conv_MURRAYLINK_SA"
    data["convdc"]["6"]["name"] = "conv_MURRAYLINK_VIC"
    data["convdc"]["7"]["name"] = "conv_3550_Q6"
    data["convdc"]["8"]["name"] = "conv_Q6_3550"
    data["convdc"]["9"]["name"] = "conv_1011_N2_1"
    data["convdc"]["10"]["name"] = "conv_1011_N2_2"
    data["convdc"]["11"]["name"] = "conv_N2_1011_1"
    data["convdc"]["12"]["name"] = "conv_N2_1011_2"
    data["convdc"]["13"]["name"] = "conv_1097_N4_1"
    data["convdc"]["14"]["name"] = "conv_1097_N4_2"
    data["convdc"]["15"]["name"] = "conv_N4_1097_1"
    data["convdc"]["16"]["name"] = "conv_N4_1097_2"
    data["convdc"]["17"]["name"] = "conv_MARINUS_VIC_1"
    data["convdc"]["18"]["name"] = "conv_MARINUS_VIC_2"
    data["convdc"]["19"]["name"] = "conv_MARINUS_TAS_1"
    data["convdc"]["20"]["name"] = "conv_MARINUS_TAS_2"
end

# copy xy coordinates from nem_2000
function copy_xy_coordinates_from_nem_2000!(data, nem_2000_dir)
    include(joinpath(nem_2000_dir, "scripts", "prepare_nem_2000.jl"))
    nem_2000_xy = Dict([
        v["name"] => Dict("x" => v["x"], "y" => v["y"])
        for (k, v) in nem_2000["bus"]
    ])

    for (b, bus) in data["bus"]
        if haskey(nem_2000_xy, bus["name"])
            bus["x"] = nem_2000_xy[bus["name"]]["x"]
            bus["y"] = nem_2000_xy[bus["name"]]["y"]
        else
            con_branch_id = find_elm(data["branch"], bus["index"], "t_bus")
            if con_branch_id != []
                closest_bus = data["bus"]["$(data["branch"]["$(con_branch_id)"]["f_bus"])"]
                println("$(bus["name"]) xy coordinates assigned relative to $(closest_bus["name"])")
                bus["x"] = closest_bus["x"] + 10
                bus["y"] = closest_bus["y"] + 10
            else
                connected_converter_id = find_elm(data["convdc"], bus["index"], "busac_i")[1]
                rez_dc_bus_id = data["convdc"]["$(connected_converter_id)"]["busdc_i"]
                dc_branch_id = find_elm(data["branchdc"], rez_dc_bus_id, "tbusdc")[1]
                con_dc_bus_id = data["branchdc"]["$(dc_branch_id)"]["fbusdc"]
                remote_converter_id = find_elm(data["convdc"], con_dc_bus_id, "busdc_i")[1]
                closest_bus_id = data["convdc"][string(remote_converter_id)]["busac_i"]
                closest_bus = data["bus"]["$(closest_bus_id)"]
                println("$(bus["name"]) xy coordinates assigned relative to $(closest_bus["name"])")
                bus["x"] = closest_bus["x"] + 10
                bus["y"] = closest_bus["y"] + 10
            end
        end
    end
end

# Add missing governors (any gens where TGOV -> HYGOV or vice versa)
# all parameters are the same for every governor
function add_missing_governors!(output_dfs, nem_2000_isphvdc)
    for (g, gen) in nem_2000_isphvdc["gen"]
        if (
            gen["powerfactory_model"] == "hydro_generator" &&
            "$(gen["name"]).ElmSym" ∉ output_dfs["ElmDsl"]["HYGOV"].con_gen
        )
            push!(
                output_dfs["ElmDsl"]["HYGOV"],
                [
                    "HYOV_$(gen["name"])", #elm_loc_name
                    1.2,    #elm_At
                    0.2,    #elm_Dturb
                    1,  #elm_Gmax
                    0.08,   #elm_Gmin
                    0.05,   #elm_R
                    0.05,   #elm_Tf
                    0.5,    #elm_Tg
                    6,  #elm_Tr
                    2,  #elm_Tw
                    0.167,  #elm_Velm
                    0.08,   #elm_qnl
                    0.5,    #elm_r
                    "$(gen["name"]).ElmSym", #con_gen
                ]
            )
            println("Added HYGOV for $(gen["name"])")
        elseif (
            gen["powerfactory_model"] == "thermal_generator" &&
            "$(gen["name"]).ElmSym" ∉ output_dfs["ElmDsl"]["TGOV1"].con_gen
        )
            push!(
                output_dfs["ElmDsl"]["TGOV1"],
                [
                    "TGOV1_$(gen["name"])", #elm_loc_name
                    0.05,   #elm_R
                    0,  #elm_Dt
                    0.5,    #elm_T1
                    2.1,    #elm_T2
                    7,  #elm_T3
                    1,  #elm_Vmax
                    0,  #elm_Vmin
                    "$(gen["name"]).ElmSym", #con_gen
                ]
            )
            println("Added TGOV1 for $(gen["name"])")
        end
    end
end

# Powerfactory doesnt allow rated power to be zero, so we set it to 1e-6
function fix_zero_rated_power_gens!(output_dfs)
    for row in eachrow(output_dfs["ElmSym"])
        if row.typ_sgn == 0
            row.typ_sgn = 1e-6
        end
    end
    for row in eachrow(output_dfs["ElmGenstat"])
        if row.elm_sgn == 0
            row.elm_sgn = 1e-6
        end
    end
    for row in eachrow(output_dfs["ElmPvsys"])
        if row.elm_sgn == 0
            row.elm_sgn = 1e-6
        end
    end
end

# relax undervoltage/overvoltage triggers in WECC models
function relax_REEC_A_voltage_triggers!(output_dfs; lv_trigger=0.8, hv_trigger=1.15)
    output_dfs["ElmDsl"]["REEC_A"].elm_Vdip = fill(lv_trigger, nrow(output_dfs["ElmDsl"]["REEC_A"]))
    output_dfs["ElmDsl"]["REEC_A"].elm_Vup = fill(hv_trigger, nrow(output_dfs["ElmDsl"]["REEC_A"]))
    output_dfs["ElmDsl"]["REEC_A"].elm_Vmin = fill(lv_trigger, nrow(output_dfs["ElmDsl"]["REEC_A"]))
    output_dfs["ElmDsl"]["REEC_A"].elm_Vmax = fill(hv_trigger, nrow(output_dfs["ElmDsl"]["REEC_A"]))
end

# relax undervoltage/overvoltage triggers in WECC models
function relax_REEC_B_voltage_triggers!(output_dfs; lv_trigger=0.8, hv_trigger=1.15)
    output_dfs["ElmDsl"]["REEC_B"].elm_Vdip = fill(lv_trigger, nrow(output_dfs["ElmDsl"]["REEC_B"]))
    output_dfs["ElmDsl"]["REEC_B"].elm_Vup = fill(hv_trigger, nrow(output_dfs["ElmDsl"]["REEC_B"]))
    output_dfs["ElmDsl"]["REEC_B"].elm_Vmin = fill(lv_trigger, nrow(output_dfs["ElmDsl"]["REEC_B"]))
    output_dfs["ElmDsl"]["REEC_B"].elm_Vmax = fill(hv_trigger, nrow(output_dfs["ElmDsl"]["REEC_B"]))
end

# p.u. conversion of generator parameters to new mbase
function convert_generator_parameters_to_new_mbase!(output_dfs, dir_hypersim_csvs)
    hs_gens = DataFrame(CSV.File(joinpath(dir_hypersim_csvs, "Gen.csv"), skipto=4))
    hs_gen_mbase = Dict(
        row["Component \r"] => row["Base Power \r"] / 1000000 for row in eachrow(hs_gens)
    )
    for row in eachrow(output_dfs["ElmSym"])
        Sb_old = hs_gen_mbase[row.elm_loc_name]
        Sb_new = row.typ_sgn
        Zb_conversion = Sb_new / Sb_old
        for param in ["xl", "xd", "xq", "xds", "xqs", "xdss", "xqss"]
            row["typ_$param"] = row["typ_$param"] * Zb_conversion
        end
        row.typ_h = row.typ_h / Zb_conversion
    end
end

# set branch shunt capacitors to be changable depending on the tap settings
function set_variable_branch_shunts!(
    output_dfs, nem_2000_isphvdc;
    capacitive_step_size=0.0000001,
    n_caps=1410065407
)
    output_dfs["ElmShnt"] = deepcopy(output_dfs["ElmShnt"])
    output_dfs["ElmShnt"].elm_ncapx = fill(1, nrow(output_dfs["ElmShnt"]))
    output_dfs["ElmShnt"].elm_ncapa = fill(1, nrow(output_dfs["ElmShnt"]))
    for row in eachrow(output_dfs["ElmShnt"])
        if occursin("branch", row.elm_loc_name)
            branch_idx = split(row.elm_loc_name, "_")[3]
            if nem_2000_isphvdc["branch"][branch_idx]["tm_min"] != 1.0
                row.elm_ncapx = n_caps
                row.elm_ncapa = round(Int, row.elm_ccap / capacitive_step_size)
                if row.elm_ncapa > row.elm_ncapx
                    throw(ArgumentError("ElmShnt: $(row.elm_loc_name) has more capacitors than allowed by elm_ncapx"))
                end
                row.elm_ccap = capacitive_step_size
            end
        end
    end
end

# configure tap changers
function configure_tap_changers!(
    output_dfs, nem_2000_isphvdc;
    dutap=0.0000001,
    min_tap=-999999999,
    max_tap=999999999,
)
    output_dfs["ElmTr2"][!, :elm_nntap] = round.(Int, output_dfs["ElmTr2"].typ_dutap ./ dutap)
    output_dfs["ElmTr2"][!, :typ_dutap] = fill(dutap, nrow(output_dfs["ElmTr2"]))
    output_dfs["ElmTr2"][!, :typ_ntpmn] = [nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["tm_min"] == 1.0 ? 0 : min_tap for row in eachrow(output_dfs["ElmTr2"])]
    output_dfs["ElmTr2"][!, :typ_ntpmx] = [nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["tm_max"] == 1.0 ? 0 : max_tap for row in eachrow(output_dfs["ElmTr2"])]
end

# add powermodels index to description of all elements
function add_descriptions!(output_dfs, nem_2000_isphvdc)
    for (elm_class, elm_df) in output_dfs
        if :msc_powermodels_index ∉ propertynames(elm_df)
            println("Description not added for $elm_class")
        else
            elm_df[!, :elm_desc] = [
                "PowerModels index: $(row.msc_powermodels_index)" for row in eachrow(elm_df)
            ]
        end
    end

    # add f_bus/t_bus and name data to branches
    output_dfs["ElmLne"].elm_desc = [
        "$(row.elm_desc)\n" *
        "f_bus: $(nem_2000_isphvdc["bus"][string(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["f_bus"])]["name"])\n" *
        "t_bus: $(nem_2000_isphvdc["bus"][string(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["t_bus"])]["name"])\n" *
        "name: $(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["name"])"
        for row in eachrow(output_dfs["ElmLne"])
    ]
    output_dfs["ElmTr2"].elm_desc = [
        "$(row.elm_desc)\n" *
        "f_bus: $(nem_2000_isphvdc["bus"][string(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["f_bus"])]["name"])\n" *
        "t_bus: $(nem_2000_isphvdc["bus"][string(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["t_bus"])]["name"])\n" *
        "name: $(nem_2000_isphvdc["branch"][string(row.msc_powermodels_index)]["name"])"
        for row in eachrow(output_dfs["ElmTr2"])
    ]
end

# set convs to voltage sources
function set_convs_to_voltage_sources!(output_dfs)
    output_dfs["ElmGenstat"].elm_iSimModel = [
        occursin("conv", row.elm_loc_name) ? 2 : 0 for row in eachrow(output_dfs["ElmGenstat"])
    ]
end

# set conv model type
function set_conv_model_type!(output_dfs, type::Int)
    output_dfs["ElmGenstat"].elm_iSimModel = [
        occursin("conv", row.elm_loc_name) ? type : 0 for row in eachrow(output_dfs["ElmGenstat"])
    ]
end

function set_convs_to_static_gens!(nem_2000_isphvdc)
    for (c, conv) in nem_2000_isphvdc["convdc"]
        conv["powerfactory_model"] = "static_generator"
    end
end

function set_wtgs_to_static_gens!(nem_2000_isphvdc)
    for (g, gen) in nem_2000_isphvdc["gen"]
        if gen["powerfactory_model"] == "wind_generator"
            gen["powerfactory_model"] = "static_generator"
        end
    end
end

function set_pv_gens_to_static_gens!(nem_2000_isphvdc)
    for (g, gen) in nem_2000_isphvdc["gen"]
        if gen["powerfactory_model"] == "pv_generator"
            gen["powerfactory_model"] = "static_generator"
        end
    end
end

# assign powerfactory model types based on powermodels NDD
function set_powerfactory_model_types_from_powermodels!(nem_2000_isphvdc)
    for (g, gen) in nem_2000_isphvdc["gen"]
        if gen["type"] ∈ ["Fossil", "Thermal"]
            gen["powerfactory_model"] = "thermal_generator"
        elseif gen["type"] == "Hydro"
            gen["powerfactory_model"] = "hydro_generator"
        elseif gen["type"] == "Wind"
            gen["powerfactory_model"] = "wind_generator"
        elseif gen["type"] == "Solar"
            gen["powerfactory_model"] = "pv_generator"
        elseif gen["type"] == "NaN" || gen["type"] == "SVC"
            gen["powerfactory_model"] = "static_var_compensator"
        else
            throw(ArgumentError("Unknown generator type: $(gen["type"])"))
        end
    end
end

