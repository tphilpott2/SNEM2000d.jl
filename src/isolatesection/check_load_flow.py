import powerfactory
import importlib

from . import core
from . import parse_data

importlib.reload(core)
importlib.reload(parse_data)

from .core import *
from .parse_data import *


# print comparison of bus voltages
def print_bus_voltage_comparison(
    app, selected_bus_names, source_bus_results, digits=8, u_threshold=None
):
    run_load_flow(app)
    selected_buses = get_selected_buses(app, selected_bus_names)

    gap = 4
    bus_icon_size = 3
    max_bus_name_len = max([len(bus.loc_name) for bus in selected_buses])

    app.PrintInfo("-" * 100)
    app.PrintInfo(
        f"{'Bus':<{max_bus_name_len+gap}} | {'pf_u':<{digits+gap}} {'source_u':<{digits+gap}} {'u_diff (%)':<{digits+gap}} | {'pf_phi':<{digits+gap}} {'source_phi':<{digits+gap}} {'phi_diff':<{digits+gap}}"
    )

    vio_buses = []

    for bus in selected_buses:
        try:
            pf_u = bus.GetAttribute("m:u")
            source_u = source_bus_results[bus.loc_name]["u"]
            u_diff = 100 * (pf_u - source_u) / source_u
            pf_phi = bus.GetAttribute("m:phiu")
            source_phi = source_bus_results[bus.loc_name]["phi"]
            phi_diff = pf_phi - source_phi

            if u_threshold is not None and abs(u_diff) < u_threshold:
                continue

            vio_buses.append(bus)

            app.PrintInfo(
                f"{bus}{'':<{max_bus_name_len+gap-len(bus.loc_name)-bus_icon_size}} | {round(pf_u, digits):<{digits+gap}} {round(source_u, digits):<{digits+gap}} {round(u_diff, digits):<{digits+gap}} | {round(pf_phi, digits):<{digits+gap}} {round(source_phi, digits):<{digits+gap}} {round(phi_diff, digits):<{digits+gap}}"
            )
        except:
            raise RuntimeError(f"Error in bus voltage comparison for {bus.loc_name}")

    app.PrintInfo("-" * 100)
    return vio_buses


# print comparison of generation dispatch
def print_gen_dispatch_comparison(
    app,
    selected_gens,
    source_gen_dispatch,
    digits=8,
    p_threshold=1e-5,
    q_threshold=1e-5,
):
    run_load_flow(app)
    pf_gen_dispatch = parse_gen_dispatch_from_powerfactory(app, selected_gens)

    gap = 2
    max_gen_name_len = max([len(gen.loc_name) for gen in selected_gens])
    col_width = max(digits + 8, 14)  # Ensure column width is at least 14 characters

    header = (
        f"{'Gen':<{max_gen_name_len + gap}} | "
        f"{'pf_p_gen':>{col_width}}"
        f"{'source_p_gen':>{col_width}}"
        f"{'p_gen_diff':>{col_width}} | "
        f"{'pf_q_gen':>{col_width}}"
        f"{'source_q_gen':>{col_width}}"
        f"{'q_gen_diff':>{col_width}}"
    )

    app.PrintInfo("-" * len(header))
    app.PrintInfo(header)
    app.PrintInfo("-" * len(header))

    for gen in selected_gens:
        pf_p_gen = pf_gen_dispatch[gen.loc_name]["pg"]
        source_p_gen = source_gen_dispatch[gen.loc_name]["pg"]
        p_gen_diff = pf_p_gen - source_p_gen

        pf_q_gen = pf_gen_dispatch[gen.loc_name]["qg"]
        source_q_gen = source_gen_dispatch[gen.loc_name]["qg"]
        q_gen_diff = pf_q_gen - source_q_gen

        if abs(p_gen_diff) >= p_threshold or abs(q_gen_diff) >= q_threshold:
            app.PrintInfo(
                f"{gen.loc_name:<{max_gen_name_len + gap}} | "
                f"{pf_p_gen:>{col_width}.{digits}f}"
                f"{source_p_gen:>{col_width}.{digits}f}"
                f"{p_gen_diff:>{col_width}.{digits}f} | "
                f"{pf_q_gen:>{col_width}.{digits}f}"
                f"{source_q_gen:>{col_width}.{digits}f}"
                f"{q_gen_diff:>{col_width}.{digits}f}"
                f"{gen}"
            )

    app.PrintInfo("-" * len(header))


# runs load flow and compares bus voltages
def compare_bus_voltages(
    app,
    selected_bus_names,
    external_data_type=None,
    external_data_path=None,
    base_scenario_name=None,
    digits=8,
    u_threshold=None,
):

    # get bus results
    if external_data_type is not None and base_scenario_name is not None:
        raise ValueError(
            "Compare bus voltages: External data type and base scenario name cannot both be specified"
        )
    elif external_data_type is None and base_scenario_name is None:
        raise ValueError(
            "Compare bus voltages: External data type and base scenario name cannot both be None"
        )
    elif base_scenario_name is not None:
        # save isolated scenario
        isolated_scenario = app.GetActiveScenario()
        # activate base scenario
        base_scenario = get_operation_scenario(app, base_scenario_name)
        base_scenario.Activate()
        # get bus results
        bus_ldf_results = parse_bus_results_from_powerfactory(
            app, get_selected_buses(app, selected_bus_names)
        )
        # activate isolated scenario
        isolated_scenario.Activate()
    elif external_data_type == "pf_data":
        bus_ldf_results = parse_bus_results_from_pf_data_csv(
            app, external_data_path, selected_bus_names
        )
    elif external_data_type == "opf_result":
        bus_ldf_results = parse_bus_results_from_opf_result_csv(
            app, external_data_path, selected_bus_names
        )
    else:
        raise ValueError(
            "Compare bus voltages: External data type must be either 'pf_data' or 'opf_result'"
        )

    print_bus_voltage_comparison(
        app, selected_bus_names, bus_ldf_results, digits, u_threshold
    )


# runs load flow and compares generation dispatch
def compare_gen_dispatch(
    app,
    selected_gens,
    external_data_type=None,
    external_data_path=None,
    base_scenario_name=None,
    digits=8,
    p_threshold=1e-5,
    q_threshold=1e-5,
):
    # get gen dispatch results
    if external_data_type is not None and base_scenario_name is not None:
        raise ValueError(
            "Compare gen dispatch: External data type and base scenario name cannot both be specified"
        )
    elif external_data_type is None and base_scenario_name is None:
        raise ValueError(
            "Compare gen dispatch: External data type and base scenario name cannot both be None"
        )
    elif base_scenario_name is not None:
        # save isolated scenario
        isolated_scenario = app.GetActiveScenario()
        # activate base scenario
        base_scenario = get_operation_scenario(app, base_scenario_name)
        base_scenario.Activate()
        # get gen dispatch results
        gen_ldf_results = parse_gen_dispatch_from_powerfactory(app, selected_gens)
        # activate isolated scenario
        isolated_scenario.Activate()
    elif external_data_type == "pf_data":
        gen_ldf_results = parse_gen_dispatch_from_pf_data_csv(
            app, external_data_path, selected_gens
        )
    elif external_data_type == "opf_result":  # TODO: implement
        raise NotImplementedError(
            "Compare gen dispatch: Opf result comparison not implemented"
        )
        # gen_ldf_results = parse_gen_dispatch_from_opf_result_csv(
        #     app, external_data_path, selected_gens
        # )
    else:
        raise ValueError(
            "Compare gen dispatch: External data type must be either 'pf_data' or 'opf_result'"
        )

    print_gen_dispatch_comparison(
        app, selected_gens, gen_ldf_results, digits, p_threshold, q_threshold
    )
