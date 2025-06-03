import powerfactory
import importlib

from . import core
from . import parse_data

importlib.reload(core)
importlib.reload(parse_data)

from .core import *
from .parse_data import *


# depreceated i think
# # runs the isolate section
# def run_isolate_section(
#     app,
#     net,
#     selected_bus_names,
#     fp_source_branch_flows=None,
#     isolated_scenario_name="isolate_section",
# ):
#     app.PrintInfo(f"running isolate section")

#     # delete any existing loads created to replace branches
#     clean_loads(app, net)

#     # get the ElmTerm objects of the selected buses
#     selected_buses = get_selected_buses(app, selected_bus_names)
#     # get the elements to keep and replace
#     (elements_to_keep, elements_to_replace) = get_elements_to_keep_and_replace(
#         app, selected_buses, fp_source_branch_flows
#     )
#     # get branch flows of source network
#     if fp_source_branch_flows is None:
#         branch_flows = get_branch_flows_from_powerfactory(app, elements_to_replace)
#     else:
#         branch_flows = get_branch_flows_from_csv(
#             app, elements_to_replace, fp_source_branch_flows
#         )
#     # deactivate current operation scenario
#     scenario = app.GetActiveScenario()
#     if scenario is not None:
#         scenario.Deactivate()
#     # get out of service elements
#     out_of_service_elms = get_out_of_service_elms(app, net)
#     # make operation scenario
#     operation_scenario = make_operation_scenario(app, isolated_scenario_name)

#     # turn off all elements
#     turn_off_elms(app, net.GetContents(1))
#     # turn on relevant elements
#     turn_on_elms(
#         app, [elm for elm in elements_to_keep if elm not in out_of_service_elms]
#     )
#     # replace branches
#     replace_branches(app, net, elements_to_replace, branch_flows)
#     # save operation scenario
#     operation_scenario.Save()

#     return elements_to_keep  # for listing


# runs isolate section using a base scenario
def run_isolate_section_from_scenario(
    app,
    net,
    selected_bus_names,
    base_scenario_name=None,
    branch_flow_source_type=None,
    branch_flow_source_path=None,
    isolated_scenario_name="isolate_section",
    branch_replacement="load",
    bus_voltage_path=None,
):
    app.PrintInfo(f"running isolate section")

    # delete any existing loads created to replace branches
    clean_loads(app, net)
    # get the ElmTerm objects of the selected buses
    selected_buses = get_selected_buses(app, selected_bus_names)

    # activate base scenario, if it exists
    if base_scenario_name is None:  # deactivate any active scenario
        app.PrintWarn("Deactivating active operation scenario")
        active_scenario = app.GetActiveScenario()
        if active_scenario is not None:
            active_scenario.Deactivate()
    else:
        base_scenario = get_operation_scenario(app, base_scenario_name)
        base_scenario.Activate()

    # get the elements to keep and replace
    (elements_to_keep, elements_to_replace) = get_elements_to_keep_and_replace(
        app, selected_buses, branch_flow_source_type
    )

    # get branch flows of source network
    app.PrintInfo("Getting branch flows")
    if branch_flow_source_type is None:
        if branch_flow_source_path is not None:
            raise ValueError(
                "Branch flow source type cannot be None if branch flow source path is provided"
            )
        branch_flows = get_branch_flows_from_powerfactory(app, elements_to_replace)
    elif branch_flow_source_path is None:
        raise ValueError(
            f"Branch flow source path not provided. Branch flow source type: {branch_flow_source_type}"
        )
    elif branch_flow_source_type == "opf_result":
        branch_flows = get_branch_flows_from_opf_result_csv(
            app, elements_to_replace, branch_flow_source_path
        )
    elif branch_flow_source_type == "pf_data":
        branch_flows = get_branch_flows_from_csv(
            app, elements_to_replace, branch_flow_source_path
        )

    # get elmements that are out of service in the base scenario
    out_of_service_elms = get_out_of_service_elms(app, net)

    # make new operation scenario
    isolated_operation_scenario = make_operation_scenario(app, isolated_scenario_name)

    # turn off all elements
    app.PrintInfo("Turning off all elements")
    turn_off_elms(app, net.GetContents(1))

    # turn on relevant elements
    app.PrintInfo("Turning on relevant elements")
    turn_on_elms(
        app, [elm for elm in elements_to_keep if elm not in out_of_service_elms]
    )

    # copy setpoint from base scenario
    if base_scenario_name is not None:
        app.PrintInfo("Copying setpoint from base scenario")
        copy_setpoint_from_base_scenario(
            app, elements_to_keep, base_scenario, isolated_operation_scenario
        )

    # replace branches
    app.PrintInfo("Replacing branches")
    if branch_replacement == "load":
        replace_branches_with_loads(app, net, elements_to_replace, branch_flows)
    elif branch_replacement == "genstat":  # TODO finsih this
        raise NotImplementedError("genstat branch replacement not implemented")
        replace_branches_with_genstats(
            app, net, elements_to_replace, branch_flows, bus_voltage_path
        )
    else:
        raise ValueError(f"Invalid branch replacement type: {branch_replacement}")

    # save operation scenario
    app.PrintInfo("Saving operation scenario")
    isolated_operation_scenario.Save()

    # set temp loads to out of service in base scenario
    if base_scenario_name is not None:
        base_scenario.Activate()
        set_temp_loads_to_out_of_service(app, net)
        base_scenario.Save()
        isolated_operation_scenario.Activate()

    return elements_to_keep  # for listing
