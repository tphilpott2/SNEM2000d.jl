using CSV, DataFrames

pf_grid_size = 4.375


# writes all graphical data to csvs
function add_graphic_data!(output_dfs, data)
    # get bus xy data from powermodels
    bus_xy_df = get_bus_xy_from_powermodels(data)
    # make bus xy dict
    bus_xy_dict = get_bus_xy_dict(bus_xy_df)
    # calculate branch angles
    branch_angles = calculate_branch_angles(output_dfs, bus_xy_dict)
    # get elements connected to each bus
    bus_connection_dict = get_bus_connection_dict(output_dfs)
    # calculate bus lengths
    calculate_bus_lengths!(bus_xy_df, bus_connection_dict, branch_angles)
    # calculate connection orders
    calculate_connection_orders!(bus_connection_dict, branch_angles)

    # write graphical data to csvs
    add_bus_graphical_data!(output_dfs, bus_xy_df)
    add_gen_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    add_load_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    add_shunt_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    add_line_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict, branch_angles)
    add_tr2_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict, branch_angles)
end

###############################################################################
# GENERAL FUNCTIONS FOR PARSING XY COORDINATES AND CALCULATING ANGLES
###############################################################################

# function to get bus x-y coordinates from hypersim data
function get_bus_xy_from_hypersim_data(dir_hypersim_csvs)
    # read data
    bus_xy_df = CSV.File(joinpath(dir_hypersim_csvs, "XY Position.csv")) |> DataFrame

    # normalise so that the minimum x and y are 10
    bus_xy_df.x = bus_xy_df.x .- minimum(bus_xy_df.x) .+ 10
    bus_xy_df.y = bus_xy_df.y .- minimum(bus_xy_df.y) .+ 10

    # rename and sort 
    rename!(bus_xy_df, [:elm_loc_name, :grf_rCenterX, :grf_rCenterY])
    sort!(bus_xy_df, :elm_loc_name)
    bus_xy_df.elm_loc_name = ["bus_$(row.elm_loc_name)" for row in eachrow(bus_xy_df)]
    return bus_xy_df
end

# function to get bus x-y coordinates from powerfactory model
function get_bus_xy_from_powermodels(data)
    # get bus x-y coordinates from powermodels model
    bus_xy_df = DataFrame(
        :elm_loc_name => [bus["name"] for bus in values(data["bus"])],
        :msc_powermodels_index => [parse(Int64, k) for k in keys(data["bus"])],
        :grf_rCenterX => [bus["x"] for bus in values(data["bus"])],
        :grf_rCenterY => [bus["y"] for bus in values(data["bus"])]
    )

    # normalise so that the minimum x and y are 10
    bus_xy_df.grf_rCenterX = bus_xy_df.grf_rCenterX .- minimum(bus_xy_df.grf_rCenterX) .+ 10
    bus_xy_df.grf_rCenterY = bus_xy_df.grf_rCenterY .- minimum(bus_xy_df.grf_rCenterY) .+ 10

    # sort 
    sort!(bus_xy_df, :msc_powermodels_index)

    return bus_xy_df
end

# creates a dictionary with the bus x-y coordinates
function get_bus_xy_dict(bus_xy_df)
    return Dict(
        row.elm_loc_name => (row.grf_rCenterX, row.grf_rCenterY)
        for row in eachrow(bus_xy_df)
    )
end

# function to calculate the angle of a branch
# the f_bus represents the origin that the angle is calculated from
# f_bus and t_bus do not represent the from and to buses defined in powermodels
function calculate_branch_angle(f_bus_xy, t_bus_xy)
    # calculate the angle of the branch
    angle = atan(t_bus_xy[2] - f_bus_xy[2], t_bus_xy[1] - f_bus_xy[1])
    return angle
end

# calculate branch angles relative to each connected bus
# calculates relative to bus xy coordinates
# offset is not considered yet
# dict structure is 
# Dict{
#     branch_name => Dict{
#         bus1_name => angle,
#         bus2_name => angle,
#     }
# }
function calculate_branch_angles(output_dfs, bus_xy_dict)
    branch_angles = Dict()
    for row in eachrow(output_dfs["ElmLne"])
        bus1_xy = bus_xy_dict[row.con_bus1]
        bus2_xy = bus_xy_dict[row.con_bus2]
        # f_bus_angle = calculate_branch_angle(f_bus_xy, t_bus_xy)
        branch_angles[row.elm_loc_name] = Dict(
            row.con_bus1 => calculate_branch_angle(bus1_xy, bus2_xy),
            row.con_bus2 => calculate_branch_angle(bus2_xy, bus1_xy)
        )
    end
    for row in eachrow(output_dfs["ElmTr2"])
        lv_bus_xy = bus_xy_dict[row.con_buslv]
        hv_bus_xy = bus_xy_dict[row.con_bushv]
        # f_bus_angle = calculate_branch_angle(f_bus_xy, t_bus_xy)
        branch_angles[row.elm_loc_name] = Dict(
            row.con_bushv => calculate_branch_angle(hv_bus_xy, lv_bus_xy),
            row.con_buslv => calculate_branch_angle(lv_bus_xy, hv_bus_xy)
        )
    end
    return branch_angles
end

# create dict with the elements connected to each bus
# dict is further populated with the order of the elements later
function get_bus_connection_dict(output_dfs)
    # initialise
    bus_connection_dict = Dict(
        row.elm_loc_name => Dict{String,Any}(
            "connected_elements" => Dict(
                "branch" => [],
                "gen" => [],
                "load" => [],
                "shunt" => [],
            )
        ) for row in eachrow(output_dfs["ElmTerm"])
    )

    # add branches
    for row in eachrow(output_dfs["ElmLne"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["branch"], row.elm_loc_name)
        push!(bus_connection_dict[row.con_bus2]["connected_elements"]["branch"], row.elm_loc_name)
    end
    for row in eachrow(output_dfs["ElmTr2"])
        push!(bus_connection_dict[row.con_buslv]["connected_elements"]["branch"], row.elm_loc_name)
        push!(bus_connection_dict[row.con_bushv]["connected_elements"]["branch"], row.elm_loc_name)
    end

    # add generators
    for row in eachrow(output_dfs["ElmSym"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["gen"], row.elm_loc_name)
    end
    for row in eachrow(output_dfs["ElmGenstat"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["gen"], row.elm_loc_name)
    end
    for row in eachrow(output_dfs["ElmPvsys"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["gen"], row.elm_loc_name)
    end

    # add static var compensators
    for row in eachrow(output_dfs["ElmSvs"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["gen"], row.elm_loc_name)
    end

    # add loads
    for row in eachrow(output_dfs["ElmLod"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["load"], row.elm_loc_name)
    end

    # add shunts
    for row in eachrow(output_dfs["ElmShnt"])
        push!(bus_connection_dict[row.con_bus1]["connected_elements"]["shunt"], row.elm_loc_name)
    end

    return bus_connection_dict
end
# function get_bus_connection_dict(data)
#     # initialise
#     bus_connection_dict = Dict(
#         bus["index"] => Dict{String,Any}(
#             "connected_elements" => Dict(
#                 "branch" => [],
#                 "gen" => [],
#                 "load" => [],
#                 "shunt" => [],
#             )
#         ) for bus in values(data["bus"])
#     )

#     # add branches
#     for branch in values(data["branch"])
#         push!(bus_connection_dict[branch["f_bus"]]["connected_elements"]["branch"], branch["index"])
#         push!(bus_connection_dict[branch["t_bus"]]["connected_elements"]["branch"], branch["index"])
#     end

#     # add generators
#     for gen in values(data["gen"])
#         push!(bus_connection_dict[gen["gen_bus"]]["connected_elements"]["gen"], gen["index"])
#     end

#     # add loads
#     for load in values(data["load"])
#         push!(bus_connection_dict[load["load_bus"]]["connected_elements"]["load"], load["index"])
#     end

#     # add shunts
#     for shunt in values(data["shunt"])
#         push!(bus_connection_dict[shunt["shunt_bus"]]["connected_elements"]["shunt"], shunt["index"])
#     end

#     return bus_connection_dict
# end



# calculate bus lengths and add to bus_xy_df
function calculate_bus_lengths!(bus_xy_df, bus_connection_dict, branch_angles)
    # calculate bus lengths
    for (bus_name, bus_connection_data) in bus_connection_dict
        # initialise number of down/up elements
        n_up = 0
        n_down = 1 # initialised at 1 because of the results window 

        # count number of generators, shunts and loads. add to down elements
        n_down += length(bus_connection_data["connected_elements"]["gen"])
        n_down += length(bus_connection_data["connected_elements"]["shunt"])
        n_down += length(bus_connection_data["connected_elements"]["load"])

        # work out if branches are up or down
        for branch_name in bus_connection_data["connected_elements"]["branch"]
            if branch_angles[branch_name][bus_name] >= 0
                n_up += 1
            else
                n_down += 1
            end
        end

        # add to bus connection dict
        bus_connection_data["n_up"] = n_up
        bus_connection_data["n_down"] = n_down

        # calculate bus length expressed in number of grid squares
        # this is different to what is entered in rSizeX in powerfactory
        bus_connection_data["length"] = max(n_up, n_down) * 2
    end

    # add bus lengths to bus_xy_df
    # bus length of 1 in powerfactory fits 3 bus_connection_data
    # calculated as max(n_cons_up, n_cons_down) * 2/6
    bus_xy_df.grf_rSizeX = [bus_connection_dict[bus_name]["length"] / 6 for bus_name in bus_xy_df.elm_loc_name]
end

# calculates connection orders
# orders are calculated based on the angle of the connected elements
# results are stored in the bus_connection_dict
function calculate_connection_orders!(bus_connection_dict, branch_angles)
    for (bus_name, bus_connection_data) in bus_connection_dict
        # add order dict to bus_connection_data
        bus_connection_data["order"] = Dict(
            "up" => Dict(),
            "down" => Dict(),
        )

        # initialise order DataFrames
        connection_order_df = DataFrame(
            :elm_name => [],
            :elm_type => [],
            :angle => [],
        )

        # add branches to DataFrame
        for branch_name in bus_connection_data["connected_elements"]["branch"]
            push!(connection_order_df, (branch_name, "branch", branch_angles[branch_name][bus_name]))
        end

        # add generators, shunts and loads to DataFrame
        # all have an angle of -pi/2
        for elm_type in ["gen", "shunt", "load"]
            for elm_name in bus_connection_data["connected_elements"][elm_type]
                push!(connection_order_df, (elm_name, elm_type, -pi / 2))
            end
        end


        # split to up and down
        up_df = connection_order_df[connection_order_df.angle.>=0, :]
        down_df = connection_order_df[connection_order_df.angle.<0, :]

        # sort DataFrames
        sort!(up_df, [:angle, :elm_type], rev=true)
        sort!(down_df, [:angle, :elm_type])

        # assign orders
        for (i, row) in enumerate(eachrow(up_df))
            bus_connection_data["order"]["up"][row.elm_name] = i
        end
        for (i, row) in enumerate(eachrow(down_df))
            bus_connection_data["order"]["down"][row.elm_name] = i + 1
        end
    end
end

###############################################################################
# ADD GRAPHICAL DATA TO OUTPUT DATAFRAMES
###############################################################################
# adds graphical data to the elemnts dataframe and writes a new csv
# functions for writing graphical data overwrite the previously written network data csv

# write bus graphical data
function add_bus_graphical_data!(output_dfs, bus_xy_df)
    # copy dataframe and remove elm_loc_name column
    bus_df = select(bus_xy_df, Not(:elm_loc_name))

    # scale x and y coordinates to powerfactory grid size
    bus_df.grf_rCenterX = bus_df.grf_rCenterX .* pf_grid_size
    bus_df.grf_rCenterY = bus_df.grf_rCenterY .* pf_grid_size

    # add powerfactory symbol name
    bus_df.grf_sSymNam = ["TermStrip" for i in 1:size(bus_df)[1]]

    # join to network data
    output_dfs["ElmTerm"] = innerjoin(output_dfs["ElmTerm"], bus_df, on=:msc_powermodels_index)
end

# write gen graphical data
# includes ElmSym, ElmGenstat, ElmPvsys and ElmSvs
function add_gen_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    # initialise dataframe
    gen_df = vcat(
        select(output_dfs["ElmSym"], [:elm_loc_name, :con_bus1, :msc_powerfactory_model]),
        select(output_dfs["ElmGenstat"], [:elm_loc_name, :con_bus1, :msc_powerfactory_model]),
        select(output_dfs["ElmPvsys"], [:elm_loc_name, :con_bus1, :msc_powerfactory_model]),
        select(output_dfs["ElmSvs"], [:elm_loc_name, :con_bus1, :msc_powerfactory_model]),
    )
    gen_df.grf_rCenterX = zeros(Float64, size(gen_df, 1))
    gen_df.grf_rCenterY = zeros(Float64, size(gen_df, 1))
    gen_df.grf_sSymNam = ["" for i in 1:size(gen_df, 1)]
    gen_df.gco_rX = [Vector{Float64}(undef, 0) for i in 1:size(gen_df, 1)]
    gen_df.gco_rY = [Vector{Float64}(undef, 0) for i in 1:size(gen_df, 1)]

    # define gen sSymNams
    symnams = Dict(
        "thermal_generator" => "d_symg",
        "hydro_generator" => "d_symg",
        "synchronous_condenser" => "d_symg",
        "WECC_WTG_type_4B" => "d_genstat",
        "WECC_WTG_type_4A" => "d_genstat",
        "WECC_WTG_type_3" => "d_genstat",
        "WECC_PV" => "d_genstat",
        "static_generator" => "d_genstat",
        "static_var_compensator" => "d_svs",
    )

    # calculate coordinate values and other graphical data
    for row in eachrow(gen_df)
        # center X
        bus_left_x = bus_xy_dict[row.con_bus1][1] - bus_connection_dict[row.con_bus1]["length"] / 2
        gen_order = bus_connection_dict[row.con_bus1]["order"]["down"][row.elm_loc_name]
        row.grf_rCenterX = bus_left_x + 1 + (gen_order - 1) * 2

        # center Y
        gen_icon = bus_xy_dict[row.con_bus1][2] - 4 # gen icon is 4 units below the bus
        row.grf_rCenterY = gen_icon # grf_rCenterY aligns with the icon

        # gco coordinates
        row.gco_rX = [row.grf_rCenterX, row.grf_rCenterX]
        row.gco_rY = [gen_icon, bus_xy_dict[row.con_bus1][2]]

        # sSymNam
        row.grf_sSymNam = symnams[row.msc_powerfactory_model]
    end

    # scale x and y coordinates to powerfactory grid size
    gen_df.grf_rCenterX = gen_df.grf_rCenterX .* pf_grid_size
    gen_df.grf_rCenterY = gen_df.grf_rCenterY .* pf_grid_size
    gen_df.gco_rX = [row.gco_rX .* pf_grid_size for row in eachrow(gen_df)]
    gen_df.gco_rY = [row.gco_rY .* pf_grid_size for row in eachrow(gen_df)]

    # rename and remove columns
    select!(gen_df, Not([:con_bus1, :msc_powerfactory_model]))

    # join to output_dfs and check if any were lost
    n_ElmSym = size(output_dfs["ElmSym"])[1]
    output_dfs["ElmSym"] = innerjoin(output_dfs["ElmSym"], gen_df, on=:elm_loc_name)
    if n_ElmSym != size(output_dfs["ElmSym"])[1]
        throw(ArgumentError("ElmSym length changed after join"))
    end
    n_ElmGenstat = size(output_dfs["ElmGenstat"])[1]
    output_dfs["ElmGenstat"] = innerjoin(output_dfs["ElmGenstat"], gen_df, on=:elm_loc_name)
    if n_ElmGenstat != size(output_dfs["ElmGenstat"])[1]
        throw(ArgumentError("ElmGenstat length changed after join"))
    end
    n_ElmPvsys = size(output_dfs["ElmPvsys"])[1]
    output_dfs["ElmPvsys"] = innerjoin(output_dfs["ElmPvsys"], gen_df, on=:elm_loc_name)
    if n_ElmPvsys != size(output_dfs["ElmPvsys"])[1]
        throw(ArgumentError("ElmPvsys length changed after join"))
    end
    n_ElmSvs = size(output_dfs["ElmSvs"])[1]
    output_dfs["ElmSvs"] = innerjoin(output_dfs["ElmSvs"], gen_df, on=:elm_loc_name)
    if n_ElmSvs != size(output_dfs["ElmSvs"])[1]
        throw(ArgumentError("ElmSvs length changed after join"))
    end

end

# write load graphical data
function add_load_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    # initialise dataframe
    load_df = select(output_dfs["ElmLod"], [:elm_loc_name, :con_bus1])
    load_df.grf_rCenterX = zeros(Float64, size(load_df, 1))
    load_df.grf_rCenterY = zeros(Float64, size(load_df, 1))
    load_df.grf_sSymNam = ["d_load" for i in 1:size(load_df, 1)]
    load_df.gco_rX = [Vector{Float64}(undef, 0) for i in 1:size(load_df, 1)]
    load_df.gco_rY = [Vector{Float64}(undef, 0) for i in 1:size(load_df, 1)]

    # calculate coordinate values and other graphical data
    for row in eachrow(load_df)
        # center X
        bus_left_x = bus_xy_dict[row.con_bus1][1] - bus_connection_dict[row.con_bus1]["length"] / 2
        load_order = bus_connection_dict[row.con_bus1]["order"]["down"][row.elm_loc_name]
        row.grf_rCenterX = bus_left_x + 1 + (load_order - 1) * 2

        # center Y
        load_icon = bus_xy_dict[row.con_bus1][2] - 4 # load icon is 4 units below the bus
        row.grf_rCenterY = load_icon # grf_rCenterY aligns with the icon

        # gco coordinates
        row.gco_rX = [row.grf_rCenterX, row.grf_rCenterX]
        row.gco_rY = [load_icon, bus_xy_dict[row.con_bus1][2]]

    end

    # scale x and y coordinates to powerfactory grid size
    load_df.grf_rCenterX = load_df.grf_rCenterX .* pf_grid_size
    load_df.grf_rCenterY = load_df.grf_rCenterY .* pf_grid_size
    load_df.gco_rX = [row.gco_rX .* pf_grid_size for row in eachrow(load_df)]
    load_df.gco_rY = [row.gco_rY .* pf_grid_size for row in eachrow(load_df)]

    select!(load_df, Not(:con_bus1))

    # join to output_df
    n_ElmLod = size(output_dfs["ElmLod"])[1]
    output_dfs["ElmLod"] = innerjoin(output_dfs["ElmLod"], load_df, on=:elm_loc_name)
    if size(output_dfs["ElmLod"])[1] != n_ElmLod
        throw(ArgumentError("ElmLod dataframe has changed size"))
    end
end


# write shunt graphical data
function add_shunt_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict)
    # initialise dataframe
    shunt_df = select(output_dfs["ElmShnt"], [:elm_loc_name, :con_bus1])
    shunt_df.grf_rCenterX = zeros(Float64, size(shunt_df, 1))
    shunt_df.grf_rCenterY = zeros(Float64, size(shunt_df, 1))
    shunt_df.grf_sSymNam = ["d_shunt" for i in 1:size(shunt_df, 1)]
    shunt_df.gco_rX = [Vector{Float64}(undef, 0) for i in 1:size(shunt_df, 1)]
    shunt_df.gco_rY = [Vector{Float64}(undef, 0) for i in 1:size(shunt_df, 1)]

    # calculate coordinate values and other graphical data
    for row in eachrow(shunt_df)
        # center X
        bus_left_x = bus_xy_dict[row.con_bus1][1] - bus_connection_dict[row.con_bus1]["length"] / 2
        shunt_order = bus_connection_dict[row.con_bus1]["order"]["down"][row.elm_loc_name]
        row.grf_rCenterX = bus_left_x + 1 + (shunt_order - 1) * 2

        # center Y
        shunt_icon = bus_xy_dict[row.con_bus1][2] - 4 # shunt icon is 4 units below the bus
        row.grf_rCenterY = shunt_icon # grf_rCenterY aligns with the icon

        # gco coordinates
        row.gco_rX = [row.grf_rCenterX, row.grf_rCenterX]
        row.gco_rY = [shunt_icon, bus_xy_dict[row.con_bus1][2]]
    end

    # scale x and y coordinates to powerfactory grid size
    shunt_df.grf_rCenterX = shunt_df.grf_rCenterX .* pf_grid_size
    shunt_df.grf_rCenterY = shunt_df.grf_rCenterY .* pf_grid_size
    shunt_df.gco_rX = [row.gco_rX .* pf_grid_size for row in eachrow(shunt_df)]
    shunt_df.gco_rY = [row.gco_rY .* pf_grid_size for row in eachrow(shunt_df)]

    select!(shunt_df, Not(:con_bus1))

    # join to network data
    n_ElmShnt = size(output_dfs["ElmShnt"], 1)
    output_dfs["ElmShnt"] = innerjoin(output_dfs["ElmShnt"], shunt_df, on=:elm_loc_name)
    if size(output_dfs["ElmShnt"], 1) != n_ElmShnt
        throw(ArgumentError("Number of rows in ElmShnt has changed"))
    end
end

# write line graphical data
function add_line_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict, branch_angles)
    # initialise dataframe
    line_df = select(output_dfs["ElmLne"], [:elm_loc_name, :con_bus1, :con_bus2])
    line_df.grf_rCenterX = zeros(Float64, size(line_df, 1))
    line_df.grf_rCenterY = zeros(Float64, size(line_df, 1))
    line_df.grf_sSymNam = ["d_lin" for i in 1:size(line_df, 1)]
    line_df.gco_1_rX = [Vector{Float64}(undef, 0) for i in 1:size(line_df, 1)]
    line_df.gco_1_rY = [Vector{Float64}(undef, 0) for i in 1:size(line_df, 1)]
    line_df.gco_2_rX = [Vector{Float64}(undef, 0) for i in 1:size(line_df, 1)]
    line_df.gco_2_rY = [Vector{Float64}(undef, 0) for i in 1:size(line_df, 1)]

    # calculate coordinate values and other graphical data
    for row in eachrow(line_df)
        # get bus coordinates
        f_bus_left_x = bus_xy_dict[row.con_bus1][1] - bus_connection_dict[row.con_bus1]["length"] / 2
        t_bus_left_x = bus_xy_dict[row.con_bus2][1] - bus_connection_dict[row.con_bus2]["length"] / 2

        # get direction at each bus
        f_bus_direction = branch_angles[row.elm_loc_name][row.con_bus1] >= 0 ? "up" : "down"
        t_bus_direction = branch_angles[row.elm_loc_name][row.con_bus2] >= 0 ? "up" : "down"

        # get order of connection
        branch_order_f_bus = bus_connection_dict[row.con_bus1]["order"][f_bus_direction][row.elm_loc_name]
        branch_order_t_bus = bus_connection_dict[row.con_bus2]["order"][t_bus_direction][row.elm_loc_name]

        # get bus connection points
        f_bus_cp_x = f_bus_left_x + 1 + (branch_order_f_bus - 1) * 2
        t_bus_cp_x = t_bus_left_x + 1 + (branch_order_t_bus - 1) * 2

        # get centre points
        centre_x = (f_bus_cp_x + t_bus_cp_x) / 2
        centre_y = (bus_xy_dict[row.con_bus1][2] + bus_xy_dict[row.con_bus2][2]) / 2
        row.grf_rCenterX = centre_x
        row.grf_rCenterY = centre_y

        # gco coordinates
        row.gco_1_rX = [centre_x, f_bus_cp_x, f_bus_cp_x]
        row.gco_1_rY = [centre_y, bus_xy_dict[row.con_bus1][2], bus_xy_dict[row.con_bus1][2]]
        row.gco_2_rX = [centre_x, t_bus_cp_x, t_bus_cp_x]
        row.gco_2_rY = [centre_y, bus_xy_dict[row.con_bus2][2], bus_xy_dict[row.con_bus2][2]]

    end

    # scale x and y coordinates to powerfactory grid size
    line_df.grf_rCenterX = line_df.grf_rCenterX .* pf_grid_size
    line_df.grf_rCenterY = line_df.grf_rCenterY .* pf_grid_size
    line_df.gco_1_rX = [row.gco_1_rX .* pf_grid_size for row in eachrow(line_df)]
    line_df.gco_1_rY = [row.gco_1_rY .* pf_grid_size for row in eachrow(line_df)]
    line_df.gco_2_rX = [row.gco_2_rX .* pf_grid_size for row in eachrow(line_df)]
    line_df.gco_2_rY = [row.gco_2_rY .* pf_grid_size for row in eachrow(line_df)]

    # remove columns
    select!(line_df, Not([:con_bus1, :con_bus2]))

    # join to network data
    n_ElmLne = size(output_dfs["ElmLne"], 1)
    output_dfs["ElmLne"] = innerjoin(output_dfs["ElmLne"], line_df, on=:elm_loc_name)
    if size(output_dfs["ElmLne"], 1) != n_ElmLne
        throw(ArgumentError("Number of rows in ElmLne has changed"))
    end
end

# write transformer graphical data
function add_tr2_graphical_data!(output_dfs, bus_connection_dict, bus_xy_dict, branch_angles)

    # initialise dataframe
    tr2_df = select(output_dfs["ElmTr2"], [:elm_loc_name, :con_buslv, :con_bushv])
    tr2_df.grf_rCenterX = zeros(Float64, size(tr2_df, 1))
    tr2_df.grf_rCenterY = zeros(Float64, size(tr2_df, 1))
    tr2_df.grf_sSymNam = ["d_lin" for i in 1:size(tr2_df, 1)]
    tr2_df.gco_1_rX = [Vector{Float64}(undef, 0) for i in 1:size(tr2_df, 1)]
    tr2_df.gco_1_rY = [Vector{Float64}(undef, 0) for i in 1:size(tr2_df, 1)]
    tr2_df.gco_2_rX = [Vector{Float64}(undef, 0) for i in 1:size(tr2_df, 1)]
    tr2_df.gco_2_rY = [Vector{Float64}(undef, 0) for i in 1:size(tr2_df, 1)]

    # calculate coordinate values and other graphical data
    for row in eachrow(tr2_df)
        # get bus coordinates
        f_bus_left_x = bus_xy_dict[row.con_buslv][1] - bus_connection_dict[row.con_buslv]["length"] / 2
        t_bus_left_x = bus_xy_dict[row.con_bushv][1] - bus_connection_dict[row.con_bushv]["length"] / 2

        # get direction at each bus
        f_bus_direction = branch_angles[row.elm_loc_name][row.con_buslv] >= 0 ? "up" : "down"
        t_bus_direction = branch_angles[row.elm_loc_name][row.con_bushv] >= 0 ? "up" : "down"

        # get order of connection
        branch_order_f_bus = bus_connection_dict[row.con_buslv]["order"][f_bus_direction][row.elm_loc_name]
        branch_order_t_bus = bus_connection_dict[row.con_bushv]["order"][t_bus_direction][row.elm_loc_name]

        # get bus connection points
        f_bus_cp_x = f_bus_left_x + 1 + (branch_order_f_bus - 1) * 2
        t_bus_cp_x = t_bus_left_x + 1 + (branch_order_t_bus - 1) * 2

        # get centre points
        centre_x = (f_bus_cp_x + t_bus_cp_x) / 2
        centre_y = (bus_xy_dict[row.con_buslv][2] + bus_xy_dict[row.con_bushv][2]) / 2
        row.grf_rCenterX = centre_x
        row.grf_rCenterY = centre_y

        # gco coordinates
        row.gco_1_rX = [centre_x, f_bus_cp_x, f_bus_cp_x]
        row.gco_1_rY = [centre_y, bus_xy_dict[row.con_buslv][2], bus_xy_dict[row.con_buslv][2]]
        row.gco_2_rX = [centre_x, t_bus_cp_x, t_bus_cp_x]
        row.gco_2_rY = [centre_y, bus_xy_dict[row.con_bushv][2], bus_xy_dict[row.con_bushv][2]]

    end

    # scale x and y coordinates to powerfactory grid size
    tr2_df.grf_rCenterX = tr2_df.grf_rCenterX .* pf_grid_size
    tr2_df.grf_rCenterY = tr2_df.grf_rCenterY .* pf_grid_size
    tr2_df.gco_1_rX = [row.gco_1_rX .* pf_grid_size for row in eachrow(tr2_df)]
    tr2_df.gco_1_rY = [row.gco_1_rY .* pf_grid_size for row in eachrow(tr2_df)]
    tr2_df.gco_2_rX = [row.gco_2_rX .* pf_grid_size for row in eachrow(tr2_df)]
    tr2_df.gco_2_rY = [row.gco_2_rY .* pf_grid_size for row in eachrow(tr2_df)]

    # remove columns
    select!(tr2_df, Not([:con_buslv, :con_bushv]))

    # join to output dataframe
    n_tr2s = size(tr2_df, 1)
    output_dfs["ElmTr2"] = innerjoin(output_dfs["ElmTr2"], tr2_df, on=:elm_loc_name)
    if size(output_dfs["ElmTr2"], 1) != n_tr2s
        throw(ArgumentError("Number of transformers in ElmTr2 dataframe is not equal to number of transformers in powermodels data"))
    end
end
