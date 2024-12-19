function parse_syncgen_dynamic_params_from_hypersim_csvs(dir_hypersim_csvs)
    # extract relevant data from hypersim csv and rename columns to powerfactory attributes
    df_syncgen_dynamic_params = CSV.File(
        joinpath(dir_hypersim_csvs, "Gen.csv"), skipto=4
    ) |> DataFrame
    rename!(df_syncgen_dynamic_params, replace.(names(df_syncgen_dynamic_params), " \r" => "", "\r" => "")) # remove trailing whitespace
    rename!(df_syncgen_dynamic_params, replace.(names(df_syncgen_dynamic_params),
        "Component" => "elm_loc_name",
        # "Base Power" => "typ_sgn", # parsed from powermodels
        "Xl" => "typ_xl",
        "X0" => "typ_x0sy",
        "Xd" => "typ_xd",
        "Xq" => "typ_xq",
        "Xpd" => "typ_xds",
        "Xpq" => "typ_xqs",
        "Xppd" => "typ_xdss",
        "Xppq" => "typ_xqss",
        "Tpd0" => "typ_tds",
        "Tpq0" => "typ_tqs",
        "Tppd0" => "typ_tdss",
        "Tppq0" => "typ_tqss",
        "H [5]" => "typ_h",
        "q-axis damper" => "typ_iturbo",
        # "Reactive power minimum" => "typ_Q_min",
        # "Reactive power maximum" => "typ_Q_max",
    ))
    select!(df_syncgen_dynamic_params, filter!(n -> occursin("typ_", n) || occursin("elm_", n), names(df_syncgen_dynamic_params)))

    #make conversions
    # df_syncgen_dynamic_params.typ_sgn = df_syncgen_dynamic_params.typ_sgn ./ 1000000 # VA to MVA
    df_syncgen_dynamic_params.typ_iturbo = df_syncgen_dynamic_params.typ_iturbo .- 1 # for round rotor vs salient pole
    # df_syncgen_dynamic_params.typ_Q_min = df_syncgen_dynamic_params.typ_Q_min ./ 1000000 #  to MVar
    # df_syncgen_dynamic_params.typ_Q_max = df_syncgen_dynamic_params.typ_Q_max ./ 1000000 #  to MVar
    for row in eachrow(df_syncgen_dynamic_params)  #subtransient -> transient time constant/reactance for salient pole generators
        if row.typ_iturbo == 0
            row.typ_xqss = row.typ_xqs
            row.typ_xqs = 0
            row.typ_tqss = row.typ_tqs
            row.typ_tqs = 0
        end
    end

    # make Xq' > Xq'' for gen_1002_1
    df_syncgen_dynamic_params.typ_xqss[findfirst(row -> row.elm_loc_name == "gen_1002_1", eachrow(df_syncgen_dynamic_params))] = 0.253

    return df_syncgen_dynamic_params
end

function parse_IEEET1_params_from_hypersim_csvs(dir_hypersim_csvs)
    # extract data from hypersim csv and remove whitespace
    df_IEEET1 = CSV.File(
        joinpath(dir_hypersim_csvs, "Gen_Exciters.csv"), skipto=4
    ) |> DataFrame
    rename!(df_IEEET1, replace.(names(df_IEEET1), " [3] \r" => "", " \r" => ""))

    # parse saturation
    df_IEEET1.E1 = [parse(Float64, split.(x, " ")[2]) for x in replace.(df_IEEET1.Efd12, "]" => "")]
    df_IEEET1.E2 = [parse(Float64, split.(x, " ")[3]) for x in replace.(df_IEEET1.Efd12, "]" => "")]
    df_IEEET1.Se1 = [parse(Float64, split.(x, " ")[2]) for x in replace.(df_IEEET1.SeEfd12, "]" => "")]
    df_IEEET1.Se2 = [parse(Float64, split.(x, " ")[3]) for x in replace.(df_IEEET1.SeEfd12, "]" => "")]

    # convert name to generator name
    df_IEEET1.con_gen = ["$(replace(row.Component, "IEEET1_" => "")).ElmSym" for row in eachrow(df_IEEET1)]

    # rename columns to powerfactory attributes and filter out irrelevant columns
    select!(df_IEEET1, Not([:Description, :Efd0, :Efd12, :SeEfd12]))
    rename!(df_IEEET1, [
        :Component => :elm_loc_name,
        :Ka => :elm_Ka,
        :Ke => :elm_Ke,
        :Kf => :elm_Kf,
        :Ta => :elm_Ta,
        :Te => :elm_Te,
        :Tf => :elm_Tf,
        :Tr => :elm_Tr,
        :VRmax => :elm_Vrmax,
        :VRmin => :elm_Vrmin,
        :E1 => :elm_E1,
        :E2 => :elm_E2,
        :Se1 => :elm_Se1,
        :Se2 => :elm_Se2,
    ])

    return df_IEEET1
end

function parse_HYGOV_params_from_hypersim_csvs(dir_hypersim_csvs)
    # extract data from hypersim csv and remove whitespace
    df_HYGOV = CSV.File(
        joinpath(dir_hypersim_csvs, "Gen_Governors_HYGOV.csv"), skipto=4
    ) |> DataFrame
    rename!(df_HYGOV, replace.(names(df_HYGOV), " [3] \r" => "", " \r" => ""))

    # convert name to generator name
    df_HYGOV.con_gen = ["$(replace(row.Component, "HYGOV_" => "")).ElmSym" for row in eachrow(df_HYGOV)]


    # rename columns to powerfactory attributes and filter out irrelevant columns
    select!(df_HYGOV, Not([:Description, :W0, :Pm0]))
    rename!(
        df_HYGOV,
        [
            "Component" => "elm_loc_name"
            "At" => "elm_At"
            "Dturb" => "elm_Dturb"
            "GMAX" => "elm_Gmax"
            "GMIN" => "elm_Gmin"
            "R" => "elm_R"
            "TF" => "elm_Tf"
            "TG" => "elm_Tg"
            "TR" => "elm_Tr"
            "TW" => "elm_Tw"
            "VELM" => "elm_Velm"
            "qNL" => "elm_qnl"
            "r" => "elm_r"
        ]
    )

    return df_HYGOV
end

function parse_TGOV1_params_from_hypersim_csvs(dir_hypersim_csvs)
    # extract data from hypersim csv and remove whitespace
    df_TGOV1 = CSV.File(
        joinpath(dir_hypersim_csvs, "Gen_Governors_TGOV.csv"), skipto=4
    ) |> DataFrame
    rename!(df_TGOV1, replace.(names(df_TGOV1), " [3] \r" => "", " \r" => ""))

    # convert name to generator name
    df_TGOV1.con_gen = ["$(replace(row.Component, "TGOV1_" => "")).ElmSym" for row in eachrow(df_TGOV1)]

    # rename columns to powerfactory attributes and filter out irrelevant columns
    select!(df_TGOV1, Not(:W0))
    rename!(df_TGOV1, [
        "Component" => "elm_loc_name",
        "R" => "elm_R",
        "Dt" => "elm_Dt",
        "T1" => "elm_T1",
        "T2" => "elm_T2",
        "T3" => "elm_T3",
        "vmax" => "elm_Vmax",
        "vmin" => "elm_Vmin",
    ])

    return df_TGOV1
end

function parse_PSS2B_params_from_hypersim_csvs(dir_hypersim_csvs)
    # extract data from hypersim csv and remove whitespace
    df_PSS2B = CSV.File(
        joinpath(dir_hypersim_csvs, "Gen_Stabilizers.csv"), skipto=4
    ) |> DataFrame
    rename!(df_PSS2B, replace.(names(df_PSS2B), " \r" => ""))

    # add powerfactory settings 
    #   inputs set to rotor speed deviation and generator electrical power
    #   base value set to gen MVA base
    df_PSS2B.elm_Ic1 = [1 for x in 1:size(df_PSS2B)[1]]
    df_PSS2B.elm_Ic2 = [3 for x in 1:size(df_PSS2B)[1]]
    df_PSS2B.elm_IPB = [1 for x in 1:size(df_PSS2B)[1]]

    # convert name to generator name
    df_PSS2B.con_gen = ["$(replace(row.Component, "PSS2B_" => "")).ElmSym" for row in eachrow(df_PSS2B)]


    # rename columns to powerfactory attributes and filter out irrelevant columns
    select!(df_PSS2B, Not([:Pe0, :W0]))
    rename!(df_PSS2B, [
        :Component => :elm_loc_name,
        :Ks1 => :elm_Ks1,
        :Ks2 => :elm_Ks2,
        :Ks3 => :elm_Ks3,
        :M => :elm_M,
        :N => :elm_N,
        :T1 => :elm_Ts1,
        :T10 => :elm_Ts10,
        :T11 => :elm_Ts11,
        :T2 => :elm_Ts2,
        :T3 => :elm_Ts3,
        :T4 => :elm_Ts4,
        :T6 => :elm_T6,
        :T7 => :elm_T7,
        :T8 => :elm_T8,
        :T9 => :elm_T9,
        :Tw1 => :elm_Tw1,
        :Tw2 => :elm_Tw2,
        :Tw3 => :elm_Tw3,
        :Tw4 => :elm_Tw4,
        :VSI1max => :elm_VS1max,
        :VSI1min => :elm_VS1min,
        :VSI2max => :elm_VS2max,
        :VSI2min => :elm_VS2min,
        :VSTmax => :elm_Vstmax,
        :VSTmin => :elm_Vstmin,
        :elm_Ic1 => :elm_elm_Ic1,
        :elm_Ic2 => :elm_elm_Ic2,
        :elm_IPB => :elm_elm_IPB,
    ])

    return df_PSS2B
end
