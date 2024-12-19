###################################################################################
# MISCELLANEOUS


def header_indexer(header):
    return {val: ind for ind, val in enumerate(header)}


# deactivates the current operation scenario
def deactivate_operation_scenario(app):
    scenario = app.GetActiveScenario()
    if scenario is not None:
        scenario.Deactivate()


# deletes all loads created to replace branches
def clean_loads(app, net):
    all_elms = net.GetContents(1)
    for a in all_elms:
        if "temp_is_" in a.loc_name:
            app.PrintInfo(f"{a.loc_name} deleted")
            a.Delete()


# deletes loads and deactivates operation scenario
def clean(app, net):
    deactivate_operation_scenario(app)
    clean_loads(app, net)


# turns off all elements provided in the list
def turn_off_elms(app, elms):
    for elm in elms:
        if elm.HasAttribute("outserv"):
            elm.outserv = 1


# turns on all elements provided in the list
def turn_on_elms(app, elms):
    for elm in elms:
        if elm.HasAttribute("outserv"):
            elm.outserv = 0


# executes a load flow and raises exception if it fails
def run_load_flow(app):
    comldf = app.GetFromStudyCase("ComLdf")
    if comldf.Execute() != 0:
        raise RuntimeError("Load flow failed")
    else:
        app.PrintInfo("Load flow successful")


# prints a list
def print_list(app, elements):
    for elm in elements:
        app.PrintInfo(elm)


def set_temp_loads_to_out_of_service(app, net):
    for elm in net.GetContents(1):
        if "temp_is_" in elm.loc_name:
            elm.outserv = 1


###################################################################################
# GET STUFF


# returns a list of all out of service elements
def get_out_of_service_elms(app, net):
    out_of_service_elms = []
    for elm in net.GetContents(1):
        if elm.HasAttribute("outserv"):
            if elm.GetAttribute("outserv") == 1:
                out_of_service_elms.append(elm)
    return out_of_service_elms


# returns the ElmTerm objects of the selected buses
def get_selected_buses(app, selected_bus_names):
    #  get selected buses
    selected_buses = [
        bus
        for bus in app.GetCalcRelevantObjects("*.ElmTerm")
        if bus.loc_name in selected_bus_names
    ]
    # check if all buses are found
    if len(selected_buses) != len(selected_bus_names):
        for bus_name in selected_bus_names:
            if bus_name not in [bus.loc_name for bus in selected_buses]:
                app.PrintInfo(f"{bus_name} not found")
        raise RuntimeError("Error in bus selection")
    return selected_buses


# returns the ElmSym, ElmGenstat, and ElmPvsys objects of the selected gens
def get_selected_gens(app, selected_bus_names):
    gens = (
        app.GetCalcRelevantObjects("ElmSym")
        + app.GetCalcRelevantObjects("ElmGenstat")
        + app.GetCalcRelevantObjects("ElmPvsys")
    )
    return [
        gen
        for gen in gens
        if gen.outserv == 0 and gen.bus1.cterm.loc_name in selected_bus_names
    ]


# returns the composite model connected to an object, its contents, and connected station controllera
def get_controllers_and_composite_model(app, elm):
    controller_list = []

    # check for plant controller
    if elm.c_pmod is not None:
        controller_list.append(elm.c_pmod)
        for dsl in elm.c_pmod.GetContents():  # could also be measurement devices
            controller_list.append(dsl)
    # check for station controller
    if elm.c_pstac is not None:
        controller_list.append(elm.c_pstac)
    return controller_list


# gets the base scenario
def get_operation_scenario(app, operation_scenario_name):
    operation_scenarios_folder = app.GetProjectFolder("scen")
    try:
        operation_scenario = operation_scenarios_folder.GetContents(
            f"{operation_scenario_name}.IntScenario"
        )[0]
    except:
        raise RuntimeError(f"Operation scenario not found: {operation_scenario_name}")
    return operation_scenario


###################################################################################
# MAKE STUFF


# makes an operation scenario
def make_operation_scenario(app, operation_scenario_name):
    # get study case
    operation_scenarios_folder = app.GetProjectFolder("scen")

    # create operation scenario
    if (
        operation_scenarios_folder.GetContents(f"{operation_scenario_name}.IntScenario")
        != []
    ):
        for scenario in operation_scenarios_folder.GetContents(
            f"{operation_scenario_name}.IntScenario"
        ):
            scenario.Deactivate()
            scenario.Delete()

    operation_scenario = operation_scenarios_folder.CreateObject("IntScenario")
    operation_scenario.loc_name = operation_scenario_name
    operation_scenario.Activate()
    return operation_scenario


# makes a load to replace a branch
def make_replacement_load(app, net, bus, branch, p, q):
    #   make load
    load = net.CreateObject("ElmLod")
    load.loc_name = f"temp_is_{branch.loc_name}"
    #   make cubicle and connect
    cub = bus.CreateObject("StaCubic")
    cub.loc_name = f"temp_is_cub_{branch.loc_name}"
    load.SetAttribute("bus1", cub)
    cub.SetAttribute("obj_id", load)
    #   set demand
    load.plini = p
    load.qlini = q
    app.PrintInfo(f"Made replacement load {load} at {bus}")


# makes a static generator at a bus
def make_static_gen(app, net, bus, Vset):
    #   make generator
    gen = net.CreateObject("ElmGenstat")
    gen.loc_name = f"temp_is_gen_{bus.loc_name}"
    #   make cubicle and connect
    cub = bus.CreateObject("StaCubic")
    cub.loc_name = f"temp_is_cub_{bus.loc_name}"
    gen.SetAttribute("bus1", cub)
    cub.SetAttribute("obj_id", gen)
    #   set demand
    gen.usetp = Vset
    gen.av_mode = "constv"
    app.PrintInfo(f"Made static gen {gen} at {bus}")


###################################################################################
# CORE ISOLATOR FUNCTIONS


# returns true if both buses of the ElmTr2 object are in the selected buses
def check_tr2_connection(app, elm, selected_buses):
    if elm.buslv.cterm not in selected_buses:
        return False
    elif elm.bushv.cterm not in selected_buses:
        return False
    else:
        return True


# returns true if both buses of the ElmLne object are in the selected buses
def check_line_connection(app, elm, selected_buses):
    if elm.bus1.cterm not in selected_buses:
        return False
    elif elm.bus2.cterm not in selected_buses:
        return False
    else:
        return True


# checks if the shunt represents charging susceptance for transformers that have been merged with a transmission line
# if so, and the results are taken from external csvs (assumed to be powermodels), then the shunt is only kept if the connected branch is within the selected area
# returns true if the shunt is to be kept
def check_shunt_connection(app, elm, selected_buses, branch_flow_source_type):
    # if the branch flow results are taken from powerfactory, then the shunt must be kept because the branch flow results used to create the replacement load do not include the shunt
    if branch_flow_source_type is None:
        return True
    elif "branch" in elm.loc_name:
        branch_name = f"{elm.loc_name.split('_')[1]}_{elm.loc_name.split('_')[2]}"
        branch = app.GetCalcRelevantObjects(f"{branch_name}.ElmTr2")[0]
        if (
            branch.buslv.cterm in selected_buses
            and branch.bushv.cterm in selected_buses
        ):
            return True
        else:
            return False
    else:

        return True


# returns the elements to keep and replace
# elements to replace are in a list of tuples of the element to replace and the bus it is connected to
# i.e (elm, bus)
def get_elements_to_keep_and_replace(app, selected_buses, branch_flow_source_type):
    # initialise lists
    elements_to_keep = selected_buses[:]
    elements_to_replace = []
    # iterate over selected buses
    for bus in selected_buses:
        connected_elements = bus.GetConnectedElements()
        # iterate over elements connected to bus
        for elm in connected_elements:
            elm_class = elm.GetClassName()
            # check if element should be kept or replaced
            if elm_class in ["ElmSym", "ElmGenstat", "ElmPvsys", "ElmSvs"]:  # gens
                elements_to_keep.append(elm)
                # check for controllers
                elements_to_keep.extend(get_controllers_and_composite_model(app, elm))
            elif elm_class == "ElmLod":  # loads
                elements_to_keep.append(elm)
            elif elm_class == "ElmShnt":  # shunts
                if check_shunt_connection(
                    app, elm, selected_buses, branch_flow_source_type
                ):
                    elements_to_keep.append(elm)
            elif elm_class == "ElmTr2":
                if check_tr2_connection(app, elm, selected_buses):
                    elements_to_keep.append(elm)
                else:
                    elements_to_replace.append((elm, bus))
            elif elm_class == "ElmLne":
                if check_line_connection(app, elm, selected_buses):
                    elements_to_keep.append(elm)
                else:
                    elements_to_replace.append((elm, bus))

    return set(elements_to_keep), set(elements_to_replace)


# replaces all branches in the elements_to_replace list
def replace_branches_with_loads(app, net, elements_to_replace, branch_flows):
    for branch, bus in elements_to_replace:
        if bus.loc_name == branch_flows[branch.loc_name]["f_bus"]:
            make_replacement_load(
                app,
                net,
                bus,
                branch,
                branch_flows[branch.loc_name]["pf"],
                branch_flows[branch.loc_name]["qf"],
            )
        elif bus.loc_name == branch_flows[branch.loc_name]["t_bus"]:
            make_replacement_load(
                app,
                net,
                bus,
                branch,
                branch_flows[branch.loc_name]["pt"],
                branch_flows[branch.loc_name]["qt"],
            )
        else:
            raise RuntimeError("Error in branch replacement")


# TODO: this is not finished. need to get bus voltages from external data and use them to set the usetp of the gens
# replaces all branches in the elements_to_replace list
def replace_branches_with_genstats(
    app,
    net,
    elements_to_replace,
    branch_flows,
):
    # make dict of buses to replace
    boundary_buses = {}
    for branch, bus in elements_to_replace:
        if bus not in boundary_buses.keys():
            boundary_buses[bus] = []
        boundary_buses[bus].append(branch)
    for bus, branches in boundary_buses.items():
        p_sum = 0
        q_sum = 0
        for branch in branches:
            if bus.loc_name == branch_flows[branch.loc_name]["f_bus"]:
                p_sum += branch_flows[branch.loc_name]["pf"]
                q_sum += branch_flows[branch.loc_name]["qf"]
            elif bus.loc_name == branch_flows[branch.loc_name]["t_bus"]:
                p_sum += branch_flows[branch.loc_name]["pt"]
                q_sum += branch_flows[branch.loc_name]["qt"]
        make_static_gen(app, net, bus, p_sum, q_sum)


# fixes the boundary conditions by adding static gens at the boundary buses
def fix_boundary_conditions(app, net, elements_to_replace, bus_voltages):
    boundary_buses = set([bus for branch, bus in elements_to_replace])
    for bus in boundary_buses:
        con_elms = bus.GetConnectedElements()
        make_gen = True
        for con_elm in con_elms:
            if con_elm.GetClassName() in ["ElmSym", "ElmGenstat", "ElmPvsys"]:
                app.PrintWarn(
                    f"Boundary condition fix not implemented for {bus} due to {con_elm}"
                )
                make_gen = False
                break
        if make_gen:
            make_static_gen(app, net, bus, bus_voltages[bus.loc_name]["u"])


# copies setpoints from the base scenario to the operation scenario
def copy_setpoint_from_base_scenario(
    app, elements_to_copy, base_scenario, operation_scenario
):
    base_scenario.Activate()
    vars_to_copy = {
        "ElmSym": ["e:pgini", "e:qgini", "e:usetp"],
        "ElmGenstat": ["e:pgini", "e:qgini", "e:usetp"],
        "ElmPvsys": ["e:pgini", "e:qgini", "e:usetp"],
        "ElmTr2": ["e:nntap"],
        "ElmLod": ["e:plini", "e:qlini"],
        "ElmStactrl": ["e:usetp"],
        "ElmShnt": ["e:ncapa"],
        "ElmComp": [],
        "ElmDsl": [],
        "ElmTerm": [],
        "ElmLne": [],
        "StaPqmea": [],
        "StaVmea": [],
        "StaCubic": [],
        "StaSwitch": [],
        "ElmSvs": ["e:qsetp"],
    }
    data_to_copy = {}
    for elm in elements_to_copy:
        elm_class = elm.GetClassName()
        data_to_copy[elm] = {}
        for var in vars_to_copy[elm_class]:
            data_to_copy[elm][var] = elm.GetAttribute(var)
        # if elm_class in ["ElmSym", "ElmGenstat", "ElmPvsys"]:
        #     if elm.c_pstac is not None:
        #         for var in vars_to_copy["ElmStactrl"]:
        #             data_to_copy[elm.c_pstac][var] = elm.c_pstac.GetAttribute(var)

    operation_scenario.Activate()
    for elm, data in data_to_copy.items():
        for var, val in data.items():
            elm.SetAttribute(var, val)
