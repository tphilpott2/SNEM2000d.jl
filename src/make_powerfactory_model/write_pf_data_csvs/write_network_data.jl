include(joinpath(@__DIR__, "parse_hypersim_csvs.jl"))

# write dataframes to csvs
function write_pf_data_csvs(output_dir, output_dfs; prefix="pf_data_", clear=false)
    if clear
        rm(output_dir, recursive=true)
        mkdir(output_dir)
        println("Cleared: '$output_dir'")
    end
    # make directories
    if !isdir(output_dir)
        mkdir(output_dir)
        println("Created: '$output_dir'")
    end
    if !isdir("$(output_dir)\\dsl_csvs") && "ElmDsl" ∈ keys(output_dfs)
        mkdir("$(output_dir)\\dsl_csvs")
        println("Created: '$(output_dir)\\dsl_csvs'")
    end
    # write csvs
    for (df_name, df) in output_dfs
        if df_name == "ElmDsl"
            for (dsl_name, dsl_df) in df
                if size(dsl_df, 1) > 0
                    CSV.write(joinpath(output_dir, "dsl_csvs", "$(prefix)$dsl_name.csv"), dsl_df)
                end
            end
        else
            if size(df, 1) > 0
                CSV.write(joinpath(output_dir, "$(prefix)$df_name.csv"), df)
            end
        end
    end
end


# prepares dataframes to be written to csvs
function prepare_output_dfs(data, dir_hypersim_csvs)
    # prepare output dfs
    output_dfs = Dict()
    println("Preparing output dataframes:")
    output_dfs["ElmTerm"] = @timed_print "ElmTerm" prepare_output_df_buses(data)
    output_dfs["ElmStactrl"] = @timed_print "ElmStactrl" prepare_output_df_station_controllers(data)
    (output_dfs["ElmLne"], output_dfs["ElmTr2"]) = @timed_print "ElmLne & ElmTr2" prepare_output_df_branches(data)
    gen_dfs = @timed_print "ElmSym, ElmGenstat, ElmPvsys, ElmSvs" prepare_output_df_gens(data, dir_hypersim_csvs, output_dfs["ElmStactrl"])
    for (df_name, gen_df) in gen_dfs
        output_dfs[df_name] = gen_df
    end
    output_dfs["ElmLod"] = @timed_print "ElmLod" prepare_output_df_loads(data)
    output_dfs["ElmShnt"] = @timed_print "ElmShnt" prepare_output_df_shunts(data)
    # process converters
    # this will need to change for modelling as anything other than static generators
    if "convdc" ∈ keys(data)
        conv_df = prepare_output_df_converters(data, output_dfs["ElmStactrl"])
        output_dfs["ElmGenstat"] = @timed_print "ElmGenstat (converters)" vcat(output_dfs["ElmGenstat"], conv_df)
    end
    return output_dfs
end

###############################################################################
# NETWORK ELEMENTS
###############################################################################

function prepare_output_df_buses(data)
    buses = data["bus"]

    # define areas
    area_names = Dict(
        1 => "NSW",
        2 => "VIC",
        3 => "QLD",
        4 => "SA",
        5 => "TAS",
    )

    # write bus data to dataframe
    bus_df = DataFrame(
        :elm_loc_name => [v["name"] for (k, v) in buses],
        :elm_uknom => [v["base_kv"] for (k, v) in buses],
        :elm_cpArea => [area_names[v["area"]] for (k, v) in buses],
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in buses],
        :res_u_pu => [v["vm"] for (k, v) in buses],
        :res_phi_rad => [v["va"] for (k, v) in buses],
    )
    sort!(bus_df, :elm_loc_name)

    return bus_df
end

function prepare_output_df_station_controllers(data)
    # get generators and connected buses
    gen_df = DataFrame(
        :name => [v["name"] for (k, v) in data["gen"]],
        :bus => [v["gen_bus"] for (k, v) in data["gen"]],
        :powerfactory_model => [v["powerfactory_model"] for (k, v) in data["gen"]],
    )

    # filter out static var compensators, as they are modelled as Q controlled units in powerfactory
    # including them in the station controller will result in a mismatch between powermodels and powerfactory
    filter!(row -> row["powerfactory_model"] != "static_var_compensator", gen_df)
    select!(gen_df, Not(:powerfactory_model))

    # get converters and connected buses
    conv_df = DataFrame(
        :name => [v["name"] for (k, v) in data["convdc"]],
        :bus => [v["busac_i"] for (k, v) in data["convdc"]],
    )

    # merge generator and converter dfs
    df = vcat(gen_df, conv_df)
    df.bus = string.(df.bus)

    # find buses with multiple generators/dc converters
    bus_df = DataFrame(
        :name => [v["name"] for (k, v) in data["bus"]],
        :ind => [k for (k, v) in data["bus"]],
    )
    bus_df.n_gens = [sum(df.bus .== string(row["ind"])) for row in eachrow(bus_df)]
    filter!(row -> row["n_gens"] > 1, bus_df)

    # make station controller df
    stactrl_df = DataFrame(
        :elm_loc_name => ["stactrl_$(row.name)" for row in eachrow(bus_df)],
        :con_bus => bus_df.name,
        :elm_usetp => [data["bus"][row.ind]["vm"] for row in eachrow(bus_df)],
        :elm_outserv => [0 for row in eachrow(bus_df)],
        :con_gens => [join(df.name[df.bus.==string(row["ind"])], ", ") for row in eachrow(bus_df)],
    )

    # add class data to con_gens
    # i.e. gen1.ElmSym, gen2.ElmSym, conv1.ElmGenstat
    gen_match = get_gen_match(data)
    # add converters to gen_match
    if haskey(data, "convdc")
        for (k, v) in data["convdc"]
            gen_match[k] = v["name"]
            gen_match[v["name"]] = k
        end
    end

    class_dict = Dict(
        "thermal_generator" => "ElmSym",
        "hydro_generator" => "ElmSym",
        "synchonous_condenser" => "ElmSym",
        "WECC_WTG_type_3" => "ElmGenstat",
        "WECC_WTG_type_4A" => "ElmGenstat",
        "WECC_WTG_type_4B" => "ElmGenstat",
        "WECC_PV" => "ElmPvsys",
        "static_generator" => "ElmGenstat",
    )
    for row in eachrow(stactrl_df)
        gens = split(row.con_gens, ", ")
        classes = [class_dict[data["gen"][gen_match[gen]]["powerfactory_model"]] for gen in gens]
        row.con_gens = join(["$gen.$class" for (gen, class) in zip(gens, classes)], ", ")
    end


    sort!(stactrl_df, :elm_loc_name)
    return stactrl_df
end

function prepare_output_df_branches(data)
    bus_match = get_bus_match(data)
    branches = copy(data["branch"])

    # create seperate line and transformer dicts
    # some transformers in the nem_2000 based models have a turns ratio of 1
    # these were all originally 3 winding transformers that have been converted to 2 winding transformers
    # as such they are left as is in powerfactory
    line_keys = [k for (k, v) in branches if v["transformer"] == false]
    trf_keys = [k for (k, v) in branches if v["transformer"] == true]
    lines = deepcopy(branches)
    for trf_key in trf_keys
        delete!(lines, trf_key)
    end
    trfs = deepcopy(branches)
    for line_key in line_keys
        delete!(trfs, line_key)
    end

    # make line df
    line_df = DataFrame(
        :elm_loc_name => ["branch_$k" for (k, v) in lines], # names are assigned according to branch index because of name length limits in powerfactory.
        :elm_desc => [
            "name" ∈ keys(v) ?
            "Name: $(v["name"])" : "No name available" for (k, v) in lines
        ],
        :con_bus1 => [bus_match[v["f_bus"]] for (k, v) in lines],
        :con_bus2 => [bus_match[v["t_bus"]] for (k, v) in lines],
        :elm_outserv => [abs(v["br_status"] - 1) for (k, v) in lines],
        :elm_dline => [1.0 for (k, v) in lines],     # no length info available from powermodels
        :typ_uline => [data["bus"][string(v["f_bus"])]["base_kv"] for (k, v) in lines],
        :typ_rline => [v["br_r"] * ((data["bus"][string(v["f_bus"])]["base_kv"]^2) / data["baseMVA"]) for (k, v) in lines],  # ohms
        :typ_xline => [v["br_x"] * ((data["bus"][string(v["f_bus"])]["base_kv"]^2) / data["baseMVA"]) for (k, v) in lines],  # ohms
        :typ_bline => [2 * v["b_fr"] / ((data["bus"][string(v["f_bus"])]["base_kv"]^2) / data["baseMVA"]) * 1e6 for (k, v) in lines],  # μS
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in lines],
    )


    # write to csv
    sort!(line_df, :elm_loc_name)


    # make trf df
    trf_df = DataFrame(
        :elm_loc_name => ["branch_$k" for (k, v) in trfs], # names are assigned according to branch index because of name length limits in powerfactory.
        :elm_desc => [
            "name" ∈ keys(v) ?
            "Name: $(v["name"])" : "No name available" for (k, v) in trfs
        ],
        :con_buslv => [data["bus"][string(v["f_bus"])]["base_kv"] <= data["bus"][string(v["t_bus"])]["base_kv"] ? bus_match[v["f_bus"]] : bus_match[v["t_bus"]] for (k, v) in trfs],
        :con_bushv => [data["bus"][string(v["f_bus"])]["base_kv"] > data["bus"][string(v["t_bus"])]["base_kv"] ? bus_match[v["f_bus"]] : bus_match[v["t_bus"]] for (k, v) in trfs],
        :elm_outserv => [abs(v["br_status"] - 1) for (k, v) in trfs],
        :elm_nntap => [1 for (k, v) in trfs],
        :typ_strn => [data["baseMVA"] for (k, v) in trfs],
        :typ_utrn_l => [data["bus"][string(v["f_bus"])]["base_kv"] <= data["bus"][string(v["t_bus"])]["base_kv"] ? data["bus"][string(v["f_bus"])]["base_kv"] : data["bus"][string(v["t_bus"])]["base_kv"] for (k, v) in trfs],
        :typ_utrn_h => [data["bus"][string(v["f_bus"])]["base_kv"] > data["bus"][string(v["t_bus"])]["base_kv"] ? data["bus"][string(v["f_bus"])]["base_kv"] : data["bus"][string(v["t_bus"])]["base_kv"] for (k, v) in trfs],
        :typ_r1pu => [v["br_r"] for (k, v) in trfs],
        :typ_x1pu => [v["br_x"] for (k, v) in trfs],
        :typ_dutap => [100 * (v["tap"] - 1) for (k, v) in trfs],
        :typ_tap_side => [data["bus"][string(v["f_bus"])]["base_kv"] <= data["bus"][string(v["t_bus"])]["base_kv"] ? 1 : 0 for (k, v) in trfs],
        :typ_ntpmn => [-1 for (k, v) in trfs],
        :typ_ntpmx => [1 for (k, v) in trfs], # tap settings are done by tap ratio match in powermodels
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in trfs],
    )

    # write to csv
    sort!(trf_df, :elm_loc_name)

    return line_df, trf_df
end

function prepare_output_df_loads(data)
    bus_match = get_bus_match(data)
    loads = copy(data["load"])
    load_df = DataFrame(
        :elm_loc_name => [data["load_data"][k]["name"] for (k, v) in loads],
        :con_bus1 => [bus_match[v["load_bus"]] for (k, v) in loads],
        :elm_plini => [data["baseMVA"] * v["pd"] for (k, v) in loads],
        :elm_qlini => [data["baseMVA"] * v["qd"] for (k, v) in loads],
        :elm_outserv => [abs(v["status"] - 1) for (k, v) in loads],
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in loads],
        # :pcurt => [0 for (k,v) in loads],
    )
    sort!(load_df, :elm_loc_name)

    return load_df
end

function prepare_output_df_shunts(data; freq=50)
    bus_match = get_bus_match(data)
    shunts = copy(data["shunt"])
    shunt_df = DataFrame(
        :elm_loc_name => [data["shunt_data"][k]["name"] for (k, v) in shunts],
        :con_bus1 => [bus_match[v["shunt_bus"]] for (k, v) in shunts],
        :elm_ushnm => [data["bus"][string(v["shunt_bus"])]["base_kv"] for (k, v) in shunts],
        :elm_shtype => [v["bs"] > 0 ? 2 : 1 for (k, v) in shunts],
        :elm_ccap => [v["bs"] > 0 ? v["bs"] * data["baseMVA"] * 1e6 / (2 * freq * pi * data["bus"][string(v["shunt_bus"])]["base_kv"]^2) : 0 for (k, v) in shunts],
        :elm_rlrea => [v["bs"] > 0 ? 0 : (data["bus"][string(v["shunt_bus"])]["base_kv"]^2) * 1e3 / (abs(v["bs"]) * data["baseMVA"] * 2 * freq * pi) for (k, v) in shunts],
        :msc_powermodels_index => Any[parse(Int64, k) for (k, v) in shunts],
    )

    # Branches that represent combined transformer and line elements include non-negligible charging susceptance
    # This charging susceptance is represented as shunt elements in powerfactory
    branches = copy(data["branch"])
    for (b, br) in branches
        # skip non transformers
        br["transformer"] == false ? continue : nothing

        # get base kv values
        v_fr = data["bus"][string(br["f_bus"])]["base_kv"]
        v_to = data["bus"][string(br["t_bus"])]["base_kv"]
        # v_fr == v_to ? continue : nothing

        # b_fr is referred to secondary side so tap setting needs to be accounted for
        zb_fr = ((v_fr * br["tap"])^2) / data["baseMVA"]
        zb_to = (v_to^2) / data["baseMVA"]

        # create shunts
        if br["b_fr"] > 0       # capacitive shunts f_bus
            push!(shunt_df, [
                "shunt_branch_$(b)_$(bus_match[br["f_bus"]])",
                bus_match[br["f_bus"]],
                v_fr,
                2,
                1e6 * br["b_fr"] / (2 * pi * freq * zb_fr),  #μF
                0,
                "NA",
            ])
        end
        if br["b_to"] > 0       # capacitive shunts t_bus
            push!(shunt_df, [
                "shunt_branch_$(b)_$(bus_match[br["t_bus"]])",
                bus_match[br["t_bus"]],
                v_to,
                2,
                1e6 * br["b_to"] / (2 * pi * freq * zb_to),  #μF
                0,
                "NA",
            ])
        end
    end
    sort!(shunt_df, :elm_loc_name)

    return shunt_df
end

###############################################################################
# GENERATORS, CONDENSERS, AND COMPENSATORS
###############################################################################
# seperate csvs are created depending on fuel source

# Update supported generator types list
supported_generator_types = [
    "thermal_generator",
    "hydro_generator",
    "static_generator",
    "static_var_compensator",
    "WECC_WTG_type_3",
    "WECC_WTG_type_4A",
    "WECC_WTG_type_4B",
    "WECC_PV",
]


function prepare_output_df_gens(data, dir_hypersim_csvs, stactrl_df)
    gens = copy(data["gen"])
    bus_match = get_bus_match(data)

    # parse data from all gens (note that this is updated for different generator types in the functions below)
    gen_df = DataFrame(
        :elm_loc_name => ["name" ∈ keys(v) ? v["name"] : "gen_bus_$(v["gen_bus"])" for (k, v) in gens],
        :con_bus1 => [bus_match[v["gen_bus"]] for (k, v) in gens],
        :elm_outserv => [abs(v["gen_status"] - 1) for (k, v) in gens],
        :elm_pgini => [data["baseMVA"] * v["pg"] for (k, v) in gens],
        :elm_qgini => [data["baseMVA"] * v["qg"] for (k, v) in gens],
        :elm_usetp => [data["bus"][string(v["gen_bus"])]["vm"] for (k, v) in gens],
        :elm_av_mode => ["constv" for (k, v) in gens],
        :elm_ip_ctrl => [data["bus"]["$(gen["gen_bus"])"]["bus_type"] == 3 ? 1 : 0 for (g, gen) in gens],
        :elm_sgn => [v["mbase"] for (k, v) in gens],
        :elm_ugn => [data["bus"][string(v["gen_bus"])]["base_kv"] for (k, v) in gens],
        :elm_cosn => [1.0 for (k, v) in gens],
        :qmin => [v["qmin"] * data["baseMVA"] for (k, v) in gens],
        :qmax => [v["qmax"] * data["baseMVA"] for (k, v) in gens],
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in gens],
        :msc_fuel => [v["fuel"] for (k, v) in gens],
        :msc_powerfactory_model => [v["powerfactory_model"] for (k, v) in gens],
    )

    # check that all generator types are supported
    if any(n -> n ∉ supported_generator_types, gen_df.msc_powerfactory_model)
        unsupported_gen_df = filter(row -> row.msc_powerfactory_model ∉ supported_generator_types, gen_df)
        # Assuming unsupported_gen_df has columns "name" and "msc_powerfactory_model"
        unsupported_details = join(["$(row.elm_loc_name): $(row.msc_powerfactory_model)" for row in eachrow(unsupported_gen_df)], ", ")
        throw(ArgumentError("Unsupported generator types: $unsupported_details"))
    end

    # add station controllers to gens
    stactrl_dict = Dict()
    for row in eachrow(stactrl_df)
        stactrl_gens = split(row.con_gens, ", ")
        for gen in stactrl_gens
            gen_loc_name = split(gen, ".")[1]
            stactrl_dict[gen_loc_name] = row.elm_loc_name
        end
    end
    gen_df.con_stactrl = ["NA" for row in eachrow(gen_df)]
    for row in eachrow(gen_df)
        if row.elm_loc_name in keys(stactrl_dict)
            row.con_stactrl = stactrl_dict[row.elm_loc_name]
            row.elm_av_mode = "constq"

        end
    end


    # prepare output dfs for different generator types
    synchronous_gen_dfs = prepare_output_df_synchronous_machines(gen_df, dir_hypersim_csvs)
    static_gen_df = prepare_output_df_static_gens(gen_df)
    pv_gen_df = prepare_output_df_pv_gens(gen_df)
    svs_dfs = prepare_output_df_static_var_compensators(gen_df)
    wecc_dsl_dfs = prepare_output_df_wecc_dsls(data)

    # # combine REGC_A dsls from wtgs and pv systems
    # REGC_A_df = vcat(
    #     static_gen_dfs["REGC_A"],
    #     pv_gen_dfs["REGC_A"],
    # )

    # # combine VSR dsls from wtgs and pv systems
    # VSR_df = vcat(
    #     static_gen_dfs["VSR"],
    #     pv_gen_dfs["VSR"],
    # )

    return Dict(
        "ElmSym" => synchronous_gen_dfs["ElmSym"],
        "ElmGenstat" => static_gen_df,
        "ElmPvsys" => pv_gen_df,
        "ElmSvs" => svs_dfs,
        "ElmDsl" => merge(
            Dict(
                "IEEET1" => synchronous_gen_dfs["IEEET1"],
                "PSS2B" => synchronous_gen_dfs["PSS2B"],
                "TGOV1" => synchronous_gen_dfs["TGOV1"],
                "HYGOV" => synchronous_gen_dfs["HYGOV"],
            ),
            wecc_dsl_dfs
        )
    )
end

function prepare_output_df_synchronous_machines(gen_df, dir_hypersim_csvs)
    synchronous_machine_df = filter(row -> row[:msc_powerfactory_model] ∈ [
            "thermal_generator",
            "hydro_generator",
            "synchronous_condenser",
        ], gen_df)

    # fix auto assignments in prepare_output_df_gens
    rename!(
        synchronous_machine_df,
        :elm_sgn => :typ_sgn,
        :elm_ugn => :typ_ugn,
        :elm_cosn => :typ_cosn,
        :qmin => :typ_Q_min,
        :qmax => :typ_Q_max,
    )

    # add frame data
    frame_types = Dict(
        "thermal_generator" => "SYM Frame_no droop_torque_reference",
        "hydro_generator" => "SYM Frame_no droop",
        "synchronous_condenser" => "NA",
    )
    synchronous_machine_df.msc_frame_type = [frame_types[row.msc_powerfactory_model] for row in eachrow(synchronous_machine_df)]

    # add controller data
    synchronous_machine_df.msc_avr = [row.msc_powerfactory_model == "synchronous_condenser" ? "NA" : "IEEET1" for row in eachrow(synchronous_machine_df)]
    synchronous_machine_df.msc_pss = [row.msc_powerfactory_model == "synchronous_condenser" ? "NA" : "PSS2B" for row in eachrow(synchronous_machine_df)]
    gov_types = Dict(
        "thermal_generator" => "TGOV1",
        "hydro_generator" => "HYGOV",
        "synchronous_condenser" => "NA",
    )
    synchronous_machine_df.msc_gov = [gov_types[row.msc_powerfactory_model] for row in eachrow(synchronous_machine_df)]

    # parse dynamic data from hypersim_csvs
    df_syncgen_dynamic_params = parse_syncgen_dynamic_params_from_hypersim_csvs(dir_hypersim_csvs)

    # check for synchronous generators without hypersim data
    if any(n -> n ∉ df_syncgen_dynamic_params.elm_loc_name, synchronous_machine_df.elm_loc_name)
        error("Some synchronous generators do not have dynamic data in hypersim csvs")
    end

    # add hypersim data
    synchronous_machine_df = innerjoin(synchronous_machine_df, df_syncgen_dynamic_params, on=:elm_loc_name)

    # write to csv
    sort!(synchronous_machine_df, :elm_loc_name)


    # write controller data to dsls csv
    IEEET1_df = prepare_output_df_IEEET1s([
        row.elm_loc_name for row in eachrow(synchronous_machine_df)
        if row.msc_powerfactory_model ∈ ["thermal_generator", "hydro_generator"]
    ])
    PSS2B_df = prepare_output_df_PSS2Bs([
        row.elm_loc_name for row in eachrow(synchronous_machine_df)
        if row.msc_powerfactory_model ∈ ["thermal_generator", "hydro_generator"]
    ])
    TGOV1_df = prepare_output_df_TGOV1s([
        row.elm_loc_name for row in eachrow(synchronous_machine_df)
        if row.msc_powerfactory_model == "thermal_generator"
    ])
    HYGOV_df = prepare_output_df_HYGOVs([
        row.elm_loc_name for row in eachrow(synchronous_machine_df)
        if row.msc_powerfactory_model == "hydro_generator"
    ])

    return Dict(
        "ElmSym" => synchronous_machine_df,
        "IEEET1" => IEEET1_df,
        "PSS2B" => PSS2B_df,
        "TGOV1" => TGOV1_df,
        "HYGOV" => HYGOV_df
    )
end

function prepare_output_df_static_gens(gen_df)
    static_gen_df = filter(row -> row[:msc_powerfactory_model] ∈ [
            "static_generator",
            "WECC_WTG_type_3",
            "WECC_WTG_type_4A",
            "WECC_WTG_type_4B",
        ], gen_df)


    # add frame data
    static_gen_df.msc_frame_type = ["NA" for row in eachrow(static_gen_df)]
    for row in eachrow(static_gen_df)
        if row.msc_powerfactory_model == "WECC_WTG_type_3"
            row.msc_frame_type = "Frame WECC WT Type 3"
        elseif row.msc_powerfactory_model == "WECC_WTG_type_4A"
            row.msc_frame_type = "Frame WECC WT Type 4A"
        elseif row.msc_powerfactory_model == "WECC_WTG_type_4B"
            row.msc_frame_type = "Frame WECC WT Type 4B"
        elseif row.msc_powerfactory_model == "static_generator"
            row.msc_frame_type = ""
        end
    end

    # rename columns
    rename!(
        static_gen_df,
        :qmin => :elm_cQ_min,
        :qmax => :elm_cQ_max,
    )

    # remove unnecessary columns
    select!(static_gen_df, Not(:elm_ugn))

    # sort by name
    sort!(static_gen_df, :elm_loc_name)

    # # extract wtg data
    # wtg_df = filter(row -> row[:msc_powerfactory_model] ∈ [
    #         "WECC_WTG_type_3",
    #         "WECC_WTG_type_4A",
    #         "WECC_WTG_type_4B",
    #     ], static_gen_df)

    # # write controller data to dsl csvs
    # wtg_dsl_dfs = prepare_output_df_wtg_dsls(wtg_df)

    # return Dict(
    #     "ElmGenstat" => static_gen_df,
    #     "WTGTRQ_A" => wtg_dsl_dfs["WTGTRQ_A"],
    #     "WTGPT_A" => wtg_dsl_dfs["WTGPT_A"],
    #     "WTGAR_A" => wtg_dsl_dfs["WTGAR_A"],
    #     "WTGT_A" => wtg_dsl_dfs["WTGT_A"],
    #     "REEC_A" => wtg_dsl_dfs["REEC_A"],
    #     "REGC_A" => wtg_dsl_dfs["REGC_A"],
    #     "VSR" => wtg_dsl_dfs["VSR"],
    # )
    return static_gen_df
end

function prepare_output_df_pv_gens(gen_df)
    pv_gen_df = filter(row -> row[:msc_powerfactory_model] == "WECC_PV", gen_df)

    # convert power to kW 
    pv_gen_df.elm_sgn = pv_gen_df.elm_sgn .* 1e3
    pv_gen_df.elm_pgini = pv_gen_df.elm_pgini .* 1e3
    pv_gen_df.elm_qgini = pv_gen_df.elm_qgini .* 1e3

    # rename columns
    rename!(
        pv_gen_df,
        :qmin => :elm_cQ_min,
        :qmax => :elm_cQ_max,
    )

    # convert reactive power limits from MVar to kVar
    pv_gen_df.elm_cQ_min = pv_gen_df.elm_cQ_min .* 1e3
    pv_gen_df.elm_cQ_max = pv_gen_df.elm_cQ_max .* 1e3

    # enable astable integration algorithm
    pv_gen_df.elm_iAstabint = [1 for row in eachrow(pv_gen_df)]

    # define input mode
    pv_gen_df.elm_mode_inp = [
        row.con_stactrl == "NA" ? "DEF" : "PQ" for row in eachrow(pv_gen_df)
    ]

    # remove unnecessary columns
    select!(pv_gen_df, Not(:elm_ugn))

    # add frame data
    pv_gen_df.msc_frame_type = ["Frame WECC Large-scale PV Plant" for row in eachrow(pv_gen_df)]

    # write to csv
    sort!(pv_gen_df, :elm_loc_name)

    # # write controller data to dsl csvs
    # pv_dsl_dfs = prepare_output_df_pv_dsls(pv_gen_df)

    # return Dict(
    #     "ElmPvsys" => pv_gen_df,
    #     "REEC_B" => pv_dsl_dfs["REEC_B"],
    #     "REGC_A" => pv_dsl_dfs["REGC_A"],
    #     "VSR" => pv_dsl_dfs["VSR"],
    # )

    return pv_gen_df
end

# converters are modelled as static generators in powerfactory
function prepare_output_df_converters(data, stactrl_df)
    convs = copy(data["convdc"])
    bus_match = get_bus_match(data)

    # create converter dataframe
    conv_df = DataFrame(
        :elm_loc_name => [v["name"] for (k, v) in convs],
        :msc_powermodels_index => [parse(Int64, k) for (k, v) in convs],
        :con_bus1 => [bus_match[v["busac_i"]] for (k, v) in convs],
        :elm_usetp => [data["bus"][string(v["busac_i"])]["vm"] for (k, v) in convs],
        :elm_sgn => [data["baseMVA"] * v["Pacmax"] for (k, v) in convs],
        :elm_av_mode => ["constv" for (k, v) in convs],
        :elm_outserv => [abs(v["status"] - 1) for (k, v) in convs],
        :elm_ip_ctrl => [0 for i in 1:length(keys(convs))],
        :elm_cosn => [1.0 for i in 1:length(keys(convs))],
        :elm_cQ_min => [v["Qacmin"] * data["baseMVA"] for (k, v) in convs],
        :elm_cQ_max => [v["Qacmax"] * data["baseMVA"] for (k, v) in convs],
        :msc_fuel => ["None" for i in 1:length(keys(convs))],
        :msc_powerfactory_model => [v["powerfactory_model"] for (k, v) in convs],
        :msc_frame_type => ["NA" for i in 1:length(keys(convs))],
    )

    # add dispatch data if available
    conv_df.elm_pgini = fill(0.0, nrow(conv_df))
    conv_df.elm_qgini = fill(0.0, nrow(conv_df))
    for row in eachrow(conv_df)
        i_string = string(row.msc_powermodels_index)
        if "pgrid" in keys(convs[i_string])
            row.elm_pgini = -convs[i_string]["pgrid"] * data["baseMVA"]
        end
        if "qgrid" in keys(convs[i_string])
            row.elm_qgini = -convs[i_string]["qgrid"] * data["baseMVA"]
        end
    end

    # add station controllers to converters
    stactrl_dict = Dict()
    for row in eachrow(stactrl_df)
        stactrl_gens = split(row.con_gens, ", ")
        for gen in stactrl_gens
            gen_loc_name = split(gen, ".")[1]
            stactrl_dict[gen_loc_name] = row.elm_loc_name
        end
    end
    conv_df.con_stactrl = ["NA" for row in eachrow(conv_df)]
    for row in eachrow(conv_df)
        if row.elm_loc_name in keys(stactrl_dict)
            row.con_stactrl = stactrl_dict[row.elm_loc_name]
            row.elm_av_mode = "constq"
        end
    end

    sort!(conv_df, :elm_loc_name)
    return conv_df
end

# static var compensators are modelled as reactive power controlled units in powerfactory
# see inside function for assumptions related to capability
function prepare_output_df_static_var_compensators(gen_df)
    # filter for static var compensators
    svs_df = filter(row -> row[:msc_powerfactory_model] == "static_var_compensator", gen_df)

    # define capacitor bank capacity
    # assumed to have n_capacitors number of capacitors, each with a rating of elm_sgn / n_capacitors
    n_capacitors = 10 # arbitrary choice. doesn't affect powerflow results in powerfactory
    svs_df.elm_nxcap = [n_capacitors for i in 1:size(svs_df, 1)] # number of capacitors
    svs_df.elm_qmin = [row.qmin / n_capacitors for row in eachrow(svs_df)] # reactive power output of each capacitor
    svs_df.elm_qmax = [max(row.qmax, 1.1 * abs(row.elm_qgini)) for row in eachrow(svs_df)] # reactive power rating of reactor bank
    svs_df.elm_tcrmax = [max(row.qmax, 1.1 * abs(row.elm_qgini)) for row in eachrow(svs_df)] # maximum reactive power limit of reactor bank

    # configure control mode
    # 0 = no control
    # 1 = voltage control mode
    # 2 = reactive power control mode
    svs_df.elm_i_ctrl = [2 for i in 1:size(svs_df, 1)]

    # remove unnecessary columns
    select!(
        svs_df,
        Not([
            :elm_pgini,
            :elm_ip_ctrl,
            :elm_av_mode,
            :elm_sgn,
            :elm_ugn,
            :elm_cosn,
            :qmin,
            :qmax,
            :con_stactrl
        ])
    )

    # rename setpoint column and convert negative polarity (powerfactory convention for svs is that positive is capacitive)
    rename!(svs_df, :elm_qgini => :elm_qsetp)
    svs_df.elm_qsetp = -svs_df.elm_qsetp

    # write to csv
    sort!(svs_df, :elm_loc_name)

    return svs_df
end

###############################################################################
# DYNAMIC (DSL) MODELS
###############################################################################

function prepare_output_df_IEEET1s(synchronous_gen_names)
    # parse data from hypersim csv
    df_IEEET1 = parse_IEEET1_params_from_hypersim_csvs(dir_hypersim_csvs)
    # filter out non synchronous generators (as designated in powermodels, not in hypersim)
    filter!(row -> split(row[:con_gen], ".")[1] ∈ synchronous_gen_names, df_IEEET1)
    # write csv
    sort!(df_IEEET1, :elm_loc_name)


    return df_IEEET1
end

function prepare_output_df_TGOV1s(TGOV1_gen_names)
    # parse data from hypersim csv
    df_TGOV1 = parse_TGOV1_params_from_hypersim_csvs(dir_hypersim_csvs)
    # filter for thermal generators (as designated in powermodels, not in hypersim)
    filter!(row -> split(row[:con_gen], ".")[1] ∈ TGOV1_gen_names, df_TGOV1)
    # write csv
    sort!(df_TGOV1, :elm_loc_name)

    return df_TGOV1
end

function prepare_output_df_HYGOVs(HYGOV_gen_names)
    # parse data from hypersim csv
    df_HYGOV = parse_HYGOV_params_from_hypersim_csvs(dir_hypersim_csvs)
    # filter for hydro generators (as designated in powermodels, not in hypersim)
    filter!(row -> split(row[:con_gen], ".")[1] ∈ HYGOV_gen_names, df_HYGOV)


    # write csv
    sort!(df_HYGOV, :elm_loc_name)

    return df_HYGOV
end

function prepare_output_df_PSS2Bs(PSS2B_gen_names)
    # parse data from hypersim csv
    df_PSS2B = parse_PSS2B_params_from_hypersim_csvs(dir_hypersim_csvs)
    # filter for thermal generators (as designated in powermodels, not in hypersim)
    filter!(row -> split(row[:con_gen], ".")[1] ∈ PSS2B_gen_names, df_PSS2B)
    # write csv
    sort!(df_PSS2B, :elm_loc_name)

    return df_PSS2B
end

################## WECC DSLS #########################

function get_gen_class(gen)
    if gen["powerfactory_model"] ∈ ["WECC_WTG_type_3", "WECC_WTG_type_4A", "WECC_WTG_type_4B"]
        gen_class = "ElmGenstat"
    elseif gen["powerfactory_model"] == "WECC_PV"
        gen_class = "ElmPvsys"
    elseif gen["powerfactory_model"] ∈ ["Black Coal", "Brown Coal", "Natural Gas", "Water"]
        gen_class = "ElmSym"
    else
        throw(ArgumentError("Gen model $gen[powerfactory_model] not supported"))
    end
end

function add_REEC!(wecc_dsl_dfs, gen; default_model="REEC_A")
    reec_model = "WECC_REEC" ∉ keys(gen) ? default_model : gen["WECC_REEC"]
    # check for electrical controller definition. use default_model if not defined
    if reec_model == "REEC_A"
        add_REEC_A!(wecc_dsl_dfs, gen)
    elseif reec_model == "REEC_B"
        add_REEC_B!(wecc_dsl_dfs, gen)
    elseif reec_model == "REEC_C"
        add_REEC_C!(wecc_dsl_dfs, gen)
    elseif reec_model == "REEC_D"
        add_REEC_D!(wecc_dsl_dfs, gen)
    elseif reec_model == "REEC_E"
        add_REEC_E!(wecc_dsl_dfs, gen)
    else
        throw(ArgumentError("WECC_REEC model $gen[WECC_REEC] not supported"))
    end
end

function add_REGC!(wecc_dsl_dfs, gen; default_model="REGC_B")
    reec_model = "WECC_REGC" ∉ keys(gen) ? default_model : gen["WECC_REGC"]
    if reec_model == "REGC_A"
        add_REGC_A!(wecc_dsl_dfs, gen)
    elseif reec_model == "REGC_B"
        add_REGC_B!(wecc_dsl_dfs, gen)
    elseif reec_model == "REGC_C"
        add_REGC_C!(wecc_dsl_dfs, gen)
    else
        throw(ArgumentError("WECC_REGC model $gen[WECC_REGC] not supported"))
    end
end

function add_REPC!(wecc_dsl_dfs, gen, default_model=nothing)
    reec_model = "WECC_PlantControl" ∉ keys(gen) ? default_model : gen["WECC_PlantControl"]
    if reec_model == "REPC_A"
        add_REPC_A!(wecc_dsl_dfs, gen)
    elseif reec_model == "REPC_B"
        add_REPC_B!(wecc_dsl_dfs, gen)
    elseif isequal(reec_model, nothing)
        return
    else
        throw(ArgumentError("WECC_REPC model $(gen[WECC_REPC]) not supported"))
    end
end

function add_REEC_A!(wecc_dsl_dfs, gen)
    # get gen class
    gen_class = get_gen_class(gen)

    # add blank row to dataframe
    # vec = vcat(
    #     "REEC_A_$(gen["name"])",
    #     zeros(Float64, size(wecc_dsl_dfs["REEC_A"], 2) - 2),
    #     "$(gen["name"]).$gen_class"
    # )
    # println(length(vec))
    # println(size(wecc_dsl_dfs["REEC_A"]))
    push!(
        wecc_dsl_dfs["REEC_A"],
        vcat(
            "REEC_A_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["REEC_A"], 2) - 2),
            "$(gen["name"]).$gen_class"
        ), promote=true
    )

    # set parameters to default values
    wecc_dsl_dfs["REEC_A"][end, :elm_PfFlag] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_VFlag] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Tp] = 0.05
    wecc_dsl_dfs["REEC_A"][end, :elm_Kqp] = 1.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Kqi] = 0.7
    wecc_dsl_dfs["REEC_A"][end, :elm_QFlag] = 1.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Kvp] = 1.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Kvi] = 0.7
    wecc_dsl_dfs["REEC_A"][end, :elm_Trv] = 0.01
    wecc_dsl_dfs["REEC_A"][end, :elm_db1] = -0.05
    wecc_dsl_dfs["REEC_A"][end, :elm_db2] = 0.05
    wecc_dsl_dfs["REEC_A"][end, :elm_Kqv] = 2.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Thld] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Vdip] = 0.9
    wecc_dsl_dfs["REEC_A"][end, :elm_Vup] = 1.1
    wecc_dsl_dfs["REEC_A"][end, :elm_Tiq] = 0.01
    wecc_dsl_dfs["REEC_A"][end, :elm_Tpord] = 0.01
    wecc_dsl_dfs["REEC_A"][end, :elm_PqFlag] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Imax] = 1.3
    wecc_dsl_dfs["REEC_A"][end, :elm_Thld2] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_PFlag] = 1.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Vref0] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Vref1] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Iq_frz] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Qmin] = -0.436
    wecc_dsl_dfs["REEC_A"][end, :elm_Vmin] = 0.9
    wecc_dsl_dfs["REEC_A"][end, :elm_Iql1] = -1.1
    wecc_dsl_dfs["REEC_A"][end, :elm_dPmin] = -2.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Pmin] = 0.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Qmax] = 0.436
    wecc_dsl_dfs["REEC_A"][end, :elm_Vmax] = 1.1
    wecc_dsl_dfs["REEC_A"][end, :elm_Iqh1] = 1.1
    wecc_dsl_dfs["REEC_A"][end, :elm_dPmax] = 2.0
    wecc_dsl_dfs["REEC_A"][end, :elm_Pmax] = 1.0
    wecc_dsl_dfs["REEC_A"][end, :mat_0] = "2,0,2,0"
    wecc_dsl_dfs["REEC_A"][end, :mat_1] = "1.1,1.1,1.1,1.1"
    wecc_dsl_dfs["REEC_A"][end, :mat_2] = "1.15,1,1.15,1"
end

function add_REEC_B!(wecc_dsl_dfs, gen)
    # get gen class
    gen_class = get_gen_class(gen)

    # add blank row to dataframe
    push!(
        wecc_dsl_dfs["REEC_B"],
        vcat(
            "REEC_B_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["REEC_B"], 2) - 2),
            "$(gen["name"]).$gen_class"
        )
    )

    # set parameters to default values
    wecc_dsl_dfs["REEC_B"][end, :elm_PfFlag] = 0.0
    wecc_dsl_dfs["REEC_B"][end, :elm_VFlag] = 1.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Tp] = 0.02
    wecc_dsl_dfs["REEC_B"][end, :elm_Kqp] = 1.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Kqi] = 0.7
    wecc_dsl_dfs["REEC_B"][end, :elm_QFlag] = 0.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Kvp] = 1.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Kvi] = 0.7
    wecc_dsl_dfs["REEC_B"][end, :elm_Trv] = 0.02
    wecc_dsl_dfs["REEC_B"][end, :elm_db1] = -0.05
    wecc_dsl_dfs["REEC_B"][end, :elm_db2] = 0.05
    wecc_dsl_dfs["REEC_B"][end, :elm_Kqv] = 2.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Vdip] = 0.9
    wecc_dsl_dfs["REEC_B"][end, :elm_Vup] = 1.1
    wecc_dsl_dfs["REEC_B"][end, :elm_Tiq] = 0.02
    wecc_dsl_dfs["REEC_B"][end, :elm_Tpord] = 0.02
    wecc_dsl_dfs["REEC_B"][end, :elm_PqFlag] = 0.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Imax] = 1.3
    wecc_dsl_dfs["REEC_B"][end, :elm_Vref0] = 0.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Qmin] = -0.43
    wecc_dsl_dfs["REEC_B"][end, :elm_Vmin] = 0.9
    wecc_dsl_dfs["REEC_B"][end, :elm_Iql1] = -1.44
    wecc_dsl_dfs["REEC_B"][end, :elm_Pmin] = 0.0
    wecc_dsl_dfs["REEC_B"][end, :elm_dPmin] = -999.0
    wecc_dsl_dfs["REEC_B"][end, :elm_Qmax] = 0.43
    wecc_dsl_dfs["REEC_B"][end, :elm_Vmax] = 1.1
    wecc_dsl_dfs["REEC_B"][end, :elm_Iqh1] = 1.44
    wecc_dsl_dfs["REEC_B"][end, :elm_Pmax] = 1.0
    wecc_dsl_dfs["REEC_B"][end, :elm_dPmax] = 999.0
end

function add_REEC_C!(wecc_dsl_dfs, gen)
    throw(ArgumentError("REEC_C model not implemented yet"))
end

function add_REEC_D!(wecc_dsl_dfs, gen)
    throw(ArgumentError("REEC_D model not implemented yet"))
end

function add_REEC_E!(wecc_dsl_dfs, gen)
    throw(ArgumentError("REEC_E model not implemented yet"))
end

function add_REGC_A!(wecc_dsl_dfs, gen)
    # get gen class
    gen_class = get_gen_class(gen)

    # add blank row to dataframe
    push!(
        wecc_dsl_dfs["REGC_A"],
        vcat(
            "REGC_A_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["REGC_A"], 2) - 2),
            "$(gen["name"]).$gen_class"
        )
    )

    # set parameters to default values
    wecc_dsl_dfs["REGC_A"][end, :elm_Tg] = 0.02
    wecc_dsl_dfs["REGC_A"][end, :elm_Tfltr] = 0.02
    wecc_dsl_dfs["REGC_A"][end, :elm_zerox] = 0.4
    wecc_dsl_dfs["REGC_A"][end, :elm_brkpt] = 0.9
    wecc_dsl_dfs["REGC_A"][end, :elm_lvpl1] = 1.22
    wecc_dsl_dfs["REGC_A"][end, :elm_Volim] = 1.2
    wecc_dsl_dfs["REGC_A"][end, :elm_Iolim] = -1.1
    wecc_dsl_dfs["REGC_A"][end, :elm_Khv] = 0.7
    wecc_dsl_dfs["REGC_A"][end, :elm_lvpnt0] = 0.4
    wecc_dsl_dfs["REGC_A"][end, :elm_lvpnt1] = 0.8
    wecc_dsl_dfs["REGC_A"][end, :elm_Lvplsw] = 1.0
    wecc_dsl_dfs["REGC_A"][end, :elm_Iqrmin] = -999.0
    wecc_dsl_dfs["REGC_A"][end, :elm_Iqrmax] = 999.0
    wecc_dsl_dfs["REGC_A"][end, :elm_rrpwr] = 10.0
    wecc_dsl_dfs["REGC_A"][end, :elm_iAstabint] = 1
end

function add_REGC_B!(wecc_dsl_dfs, gen)
    # get gen class
    gen_class = get_gen_class(gen)

    # add blank row to dataframe
    push!(
        wecc_dsl_dfs["REGC_B"],
        vcat(
            "REGC_B_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["REGC_B"], 2) - 2),
            "$(gen["name"]).$gen_class"
        )
    )

    wecc_dsl_dfs["REGC_B"][end, :elm_Tg] = 0.02
    wecc_dsl_dfs["REGC_B"][end, :elm_Tfltr] = 0.02
    wecc_dsl_dfs["REGC_B"][end, :elm_RateFlag] = 0.0
    wecc_dsl_dfs["REGC_B"][end, :elm_re] = 0.0
    wecc_dsl_dfs["REGC_B"][end, :elm_xe] = 0.1
    wecc_dsl_dfs["REGC_B"][end, :elm_Te] = 0.02
    wecc_dsl_dfs["REGC_B"][end, :elm_Iqrmin] = -999.0
    wecc_dsl_dfs["REGC_B"][end, :elm_Iqrmax] = 999.0
    wecc_dsl_dfs["REGC_B"][end, :elm_rrpwr] = 10.0
    wecc_dsl_dfs["REGC_B"][end, :elm_iAstabint] = 1
end

function add_REGC_C!(wecc_dsl_dfs, gen)
    throw(ArgumentError("REGC_C model not implemented yet"))
end

function add_REPC_A!(wecc_dsl_dfs, gen)
    # add blank row to dataframe
    push!(
        wecc_dsl_dfs["REPC_A"],
        vcat(
            "REPC_A_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["REPC_A"], 2) - 2),
            "$(gen["name"]).$(get_gen_class(gen))"
        )
    )

    # set parameters to default values
    wecc_dsl_dfs["REPC_A"][end, :elm_Rc] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_Xc] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_Tfltr] = 0.02
    wecc_dsl_dfs["REPC_A"][end, :elm_Tp] = 0.25
    wecc_dsl_dfs["REPC_A"][end, :elm_db] = 0.002
    wecc_dsl_dfs["REPC_A"][end, :elm_Kp] = 1
    wecc_dsl_dfs["REPC_A"][end, :elm_Ki] = 5
    wecc_dsl_dfs["REPC_A"][end, :elm_Vfrz] = 0.7
    wecc_dsl_dfs["REPC_A"][end, :elm_Tft] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_Tfv] = 0.05
    wecc_dsl_dfs["REPC_A"][end, :elm_Kc] = 10
    wecc_dsl_dfs["REPC_A"][end, :elm_FrqFlag] = 1
    wecc_dsl_dfs["REPC_A"][end, :elm_RefFlag] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_VcmpFlag] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_fdbd1] = -0.0006
    wecc_dsl_dfs["REPC_A"][end, :elm_fdbd2] = 0.0006
    wecc_dsl_dfs["REPC_A"][end, :elm_Ddn] = 20
    wecc_dsl_dfs["REPC_A"][end, :elm_Dup] = 20
    wecc_dsl_dfs["REPC_A"][end, :elm_Kpg] = 1.1
    wecc_dsl_dfs["REPC_A"][end, :elm_Kig] = 3
    wecc_dsl_dfs["REPC_A"][end, :elm_Tlag] = 0.1
    wecc_dsl_dfs["REPC_A"][end, :elm_emin] = -0.5
    wecc_dsl_dfs["REPC_A"][end, :elm_Qmin] = -0.436
    wecc_dsl_dfs["REPC_A"][end, :elm_femin] = -99
    wecc_dsl_dfs["REPC_A"][end, :elm_Pmin] = 0
    wecc_dsl_dfs["REPC_A"][end, :elm_emax] = 0.5
    wecc_dsl_dfs["REPC_A"][end, :elm_Qmax] = 0.436
    wecc_dsl_dfs["REPC_A"][end, :elm_femax] = 99
    wecc_dsl_dfs["REPC_A"][end, :elm_Pmax] = 1
end


function add_REPC_B!(wecc_dsl_dfs, gen)
    throw(ArgumentError("REPC_B model not implemented yet"))
end

function add_WTGTPT_A!(wecc_dsl_dfs, gen)
    throw(ArgumentError("WTGTPT_A model not implemented yet"))
end

function add_WTGTRQ_A!(wecc_dsl_dfs, gen)
    throw(ArgumentError("WTGTRQ_A model not implemented yet"))
end

function add_WTGAR_A!(wecc_dsl_dfs, gen)
    throw(ArgumentError("WTGAR_A model not implemented yet"))
end

function add_WTGT_A!(wecc_dsl_dfs, gen)
    # add blank row to dataframe
    push!(
        wecc_dsl_dfs["WTGT_A"],
        vcat(
            "WTGT_A_$(gen["name"])",
            zeros(Float64, size(wecc_dsl_dfs["WTGT_A"], 2) - 2),
            "$(gen["name"]).$(get_gen_class(gen))"
        )
    )

    # set parameters to default values
    wecc_dsl_dfs["WTGT_A"][end, :elm_Ht] = 5.0
    wecc_dsl_dfs["WTGT_A"][end, :elm_Dshaft] = 1.5
    wecc_dsl_dfs["WTGT_A"][end, :elm_Kshaft] = 200
    wecc_dsl_dfs["WTGT_A"][end, :elm_Hg] = 1.0
end

function prepare_output_df_wecc_dsls(data)
    # initialise dfs
    wecc_dsl_dfs = Dict{String,DataFrame}(
        "REEC_A" => DataFrame(
            :elm_loc_name => String[],
            :elm_PfFlag => Float64[],
            :elm_VFlag => Float64[],
            :elm_Tp => Float64[],
            :elm_Kqp => Float64[],
            :elm_Kqi => Float64[],
            :elm_QFlag => Float64[],
            :elm_Kvp => Float64[],
            :elm_Kvi => Float64[],
            :elm_Trv => Float64[],
            :elm_db1 => Float64[],
            :elm_db2 => Float64[],
            :elm_Kqv => Float64[],
            :elm_Thld => Float64[],
            :elm_Vdip => Float64[],
            :elm_Vup => Float64[],
            :elm_Tiq => Float64[],
            :elm_Tpord => Float64[],
            :elm_PqFlag => Float64[],
            :elm_Imax => Float64[],
            :elm_Thld2 => Float64[],
            :elm_PFlag => Float64[],
            :elm_Vref0 => Float64[],
            :elm_Vref1 => Float64[],
            :elm_Iq_frz => Float64[],
            :elm_Qmin => Float64[],
            :elm_Vmin => Float64[],
            :elm_Iql1 => Float64[],
            :elm_dPmin => Float64[],
            :elm_Pmin => Float64[],
            :elm_Qmax => Float64[],
            :elm_Vmax => Float64[],
            :elm_Iqh1 => Float64[],
            :elm_dPmax => Float64[],
            :elm_Pmax => Float64[],
            :mat_0 => String[],
            :mat_1 => String[],
            :mat_2 => String[],
            :con_gen => String[],
        ),
        "REEC_B" => DataFrame(
            :elm_loc_name => String[],
            :elm_PfFlag => Float64[],
            :elm_VFlag => Float64[],
            :elm_Tp => Float64[],
            :elm_Kqp => Float64[],
            :elm_Kqi => Float64[],
            :elm_QFlag => Float64[],
            :elm_Kvp => Float64[],
            :elm_Kvi => Float64[],
            :elm_Trv => Float64[],
            :elm_db1 => Float64[],
            :elm_db2 => Float64[],
            :elm_Kqv => Float64[],
            :elm_Vdip => Float64[],
            :elm_Vup => Float64[],
            :elm_Tiq => Float64[],
            :elm_Tpord => Float64[],
            :elm_PqFlag => Float64[],
            :elm_Imax => Float64[],
            :elm_Vref0 => Float64[],
            :elm_Qmin => Float64[],
            :elm_Vmin => Float64[],
            :elm_Iql1 => Float64[],
            :elm_Pmin => Float64[],
            :elm_dPmin => Float64[],
            :elm_Qmax => Float64[],
            :elm_Vmax => Float64[],
            :elm_Iqh1 => Float64[],
            :elm_Pmax => Float64[],
            :elm_dPmax => Float64[],
            :con_gen => String[],
        ),
        "REEC_C" => DataFrame(
            :elm_loc_name => String[],
            :elm_PfFlag => Float64[],
            :elm_VFlag => Float64[],
            :elm_Tp => Float64[],
            :elm_Kqp => Float64[],
            :elm_Kqi => Float64[],
            :elm_QFlag => Float64[],
            :elm_Kvp => Float64[],
            :elm_Kvi => Float64[],
            :elm_Trv => Float64[],
            :elm_db1 => Float64[],
            :elm_db2 => Float64[],
            :elm_Kqv => Float64[],
            :elm_Vdip => Float64[],
            :elm_Vup => Float64[],
            :elm_Tiq => Float64[],
            :elm_Tpord => Float64[],
            :elm_PqFlag => Float64[],
            :elm_Imax => Float64[],
            :elm_Vref0 => Float64[],
            :elm_T => Float64[],
            :elm_SOC0 => Float64[],
            :elm_Qmin => Float64[],
            :elm_Vmin => Float64[],
            :elm_Iql1 => Float64[],
            :elm_SCOmin => Float64[],
            :elm_dPmin => Float64[],
            :elm_Pmin => Float64[],
            :elm_Qmax => Float64[],
            :elm_Vmax => Float64[],
            :elm_Iqh1 => Float64[],
            :elm_SCOmax => Float64[],
            :elm_dPmax => Float64[],
            :elm_Pmax => Float64[],
            :elm_WGO_active => Float64[],
            :con_gen => String[],
        ),
        "REEC_D" => DataFrame(
            :elm_loc_name => String[],
            :elm_PfFlag => Float64[],
            :elm_VFlag => Float64[],
            :elm_Tp => Float64[],
            :elm_Kqp => Float64[],
            :elm_Kqi => Float64[],
            :elm_QFlag => Float64[],
            :elm_Kvp => Float64[],
            :elm_Kvi => Float64[],
            :elm_Trv => Float64[],
            :elm_dbd1 => Float64[],
            :elm_dbd2 => Float64[],
            :elm_Kqv => Float64[],
            :elm_Vdip => Float64[],
            :elm_Vup => Float64[],
            :elm_Tiq => Float64[],
            :elm_Tpord => Float64[],
            :elm_PqFlag => Float64[],
            :elm_Imax => Float64[],
            :elm_Thld2 => Float64[],
            :elm_Ke => Float64[],
            :elm_PFlag => Float64[],
            :elm_Vref0 => Float64[],
            :elm_Vref1 => Float64[],
            :elm_Rc => Float64[],
            :elm_Xc => Float64[],
            :elm_VcmpFlag => Float64[],
            :elm_Kc => Float64[],
            :elm_Tr1 => Float64[],
            :elm_vblkl => Float64[],
            :elm_vblkh => Float64[],
            :elm_Tblk_delay => Float64[],
            :elm_Thld => Float64[],
            :elm_Iqfrz => Float64[],
            :elm_qvmin => Float64[],
            :elm_Vmin => Float64[],
            :elm_Iql1 => Float64[],
            :elm_dPmin => Float64[],
            :elm_Pmin => Float64[],
            :elm_qvmax => Float64[],
            :elm_Vmax => Float64[],
            :elm_Iqh1 => Float64[],
            :elm_dPmax => Float64[],
            :elm_Pmax => Float64[],
            :elm_WGO_active => Float64[],
            :con_gen => String[],
        ),
        "REEC_E" => DataFrame(
            :elm_loc_name => String[],
            :elm_PfFlag => Float64[],
            :elm_VFlag => Float64[],
            :elm_QFlag => Float64[],
            :elm_Tp => Float64[],
            :elm_Kqp => Float64[],
            :elm_Kqi => Float64[],
            :elm_Kvp => Float64[],
            :elm_Kvi => Float64[],
            :elm_Trv => Float64[],
            :elm_dbd1 => Float64[],
            :elm_dbd2 => Float64[],
            :elm_Kqv => Float64[],
            :elm_Vdip => Float64[],
            :elm_Vup => Float64[],
            :elm_Tiq => Float64[],
            :elm_PqFlag => Float64[],
            :elm_PqFlagFRT => Float64[],
            :elm_Imax => Float64[],
            :elm_Ke => Float64[],
            :elm_PEFlag => Float64[],
            :elm_PFlag => Float64[],
            :elm_Kpp => Float64[],
            :elm_Kpi => Float64[],
            :elm_Tpord => Float64[],
            :elm_Vref0 => Float64[],
            :elm_Vref1 => Float64[],
            :elm_Rc => Float64[],
            :elm_Xc => Float64[],
            :elm_VcmpFlag => Float64[],
            :elm_Kc => Float64[],
            :elm_Tr1 => Float64[],
            :elm_vblkl => Float64[],
            :elm_vblkh => Float64[],
            :elm_Tblk_delay => Float64[],
            :elm_Thld2 => Float64[],
            :elm_Thld => Float64[],
            :elm_Iqfrz => Float64[],
            :elm_qvmin => Float64[],
            :elm_Vmin => Float64[],
            :elm_Iql1 => Float64[],
            :elm_dPmin => Float64[],
            :elm_Pmin => Float64[],
            :elm_qvmax => Float64[],
            :elm_Vmax => Float64[],
            :elm_Iqh1 => Float64[],
            :elm_dPmax => Float64[],
            :elm_Pmax => Float64[],
            :elm_WGO_active => Float64[],
            :con_gen => String[],
        ),
        "REGC_A" => DataFrame(
            :elm_loc_name => String[],
            :elm_Tg => Float64[],
            :elm_Tfltr => Float64[],
            :elm_zerox => Float64[],
            :elm_brkpt => Float64[],
            :elm_lvpl1 => Float64[],
            :elm_Volim => Float64[],
            :elm_Iolim => Float64[],
            :elm_Khv => Float64[],
            :elm_lvpnt0 => Float64[],
            :elm_lvpnt1 => Float64[],
            :elm_Lvplsw => Float64[],
            :elm_Iqrmin => Float64[],
            :elm_Iqrmax => Float64[],
            :elm_rrpwr => Float64[],
            :elm_iAstabint => Int64[],
            :con_gen => String[],
        ),
        "REGC_B" => DataFrame(
            :elm_loc_name => String[],
            :elm_Tg => Float64[],
            :elm_Tfltr => Float64[],
            :elm_RateFlag => Float64[],
            :elm_re => Float64[],
            :elm_xe => Float64[],
            :elm_Te => Float64[],
            :elm_Iqrmin => Float64[],
            :elm_Iqrmax => Float64[],
            :elm_rrpwr => Float64[],
            :elm_iAstabint => Int64[],
            :con_gen => String[],
        ),
        "REGC_C" => DataFrame(),
        "WTGTPT_A" => DataFrame(),
        "WTGTRQ_A" => DataFrame(),
        "WTGAR_A" => DataFrame(),
        "WTGT_A" => DataFrame(
            :elm_loc_name => String[],
            :elm_Ht => Float64[],
            :elm_Dshaft => Float64[],
            :elm_Kshaft => Float64[],
            :elm_Hg => Float64[],
            :con_gen => String[],
        ),
        "REPC_A" => DataFrame(
            :elm_loc_name => String[],
            :elm_Rc => Float64[],
            :elm_Xc => Float64[],
            :elm_Tfltr => Float64[],
            :elm_Tp => Float64[],
            :elm_db => Float64[],
            :elm_Kp => Float64[],
            :elm_Ki => Float64[],
            :elm_Vfrz => Float64[],
            :elm_Tft => Float64[],
            :elm_Tfv => Float64[],
            :elm_Kc => Float64[],
            :elm_FrqFlag => Float64[],
            :elm_RefFlag => Float64[],
            :elm_VcmpFlag => Float64[],
            :elm_fdbd1 => Float64[],
            :elm_fdbd2 => Float64[],
            :elm_Ddn => Float64[],
            :elm_Dup => Float64[],
            :elm_Kpg => Float64[],
            :elm_Kig => Float64[],
            :elm_Tlag => Float64[],
            :elm_emin => Float64[],
            :elm_Qmin => Float64[],
            :elm_femin => Float64[],
            :elm_Pmin => Float64[],
            :elm_emax => Float64[],
            :elm_Qmax => Float64[],
            :elm_femax => Float64[],
            :elm_Pmax => Float64[],
            :con_gen => String[],
        ),
    )

    for (g, gen) in data["gen"]
        if startswith(gen["powerfactory_model"], "WECC")
            add_REEC!(wecc_dsl_dfs, gen)
            add_REGC!(wecc_dsl_dfs, gen)
            add_REPC!(wecc_dsl_dfs, gen)

            # check for additional models for WECC_WTGs
            if gen["powerfactory_model"] == "WECC_WTG_type_3"
                add_WTGTPT_A!(wecc_dsl_dfs, gen)
                add_WTGTRQ_A!(wecc_dsl_dfs, gen)
                add_WTGAR_A!(wecc_dsl_dfs, gen)
                add_WTGT_A!(wecc_dsl_dfs, gen)
            elseif gen["powerfactory_model"] == "WECC_WTG_type_4A"
                add_WTGT_A!(wecc_dsl_dfs, gen)
            end

        end
    end

    # remove empty dfs
    for k in keys(wecc_dsl_dfs)
        if isempty(wecc_dsl_dfs[k])
            delete!(wecc_dsl_dfs, k)
        end
    end

    return wecc_dsl_dfs
end
