import os
import sys
import csv
import math
from pathlib import Path
import powerfactory


def header_indexes(header):
    return {val: ind for ind, val in enumerate(header)}


def parse_gens(app, gen_results_path, baseMVA=100):
    gens = {}
    with open(gen_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        if "alpha_g" in idx_of.keys():
            for row in reader:
                if math.isclose(float(row[idx_of["alpha_g"]]), 0.0, abs_tol=1e-5):
                    gens[row[idx_of["ind"]]] = {
                        "pgini": 0,
                        "qgini": 0,
                        "outserv": 1,
                    }
                else:
                    gens[row[idx_of["ind"]]] = {
                        "pgini": float(row[idx_of["pg"]]) * baseMVA,
                        "qgini": float(row[idx_of["qg"]]) * baseMVA,
                        "outserv": 0,
                    }
        elif "outserv" in idx_of.keys():
            for row in reader:
                gens[row[idx_of["ind"]]] = {
                    "pgini": float(row[idx_of["pg"]]) * baseMVA,
                    "qgini": float(row[idx_of["qg"]]) * baseMVA,
                    "outserv": int(row[idx_of["outserv"]]),
                }
        else:
            raise ValueError("No gen status found in gen results file")

    return gens


def parse_convs(app, conv_results_path, baseMVA=100):
    convs = {}
    with open(conv_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        for row in reader:
            convs[row[idx_of["ind"]]] = {
                "pgini": -float(row[idx_of["pgrid"]]) * baseMVA,
                "qgini": -float(row[idx_of["qgrid"]]) * baseMVA,
                "outserv": 0,
            }
    return convs


def parse_loads(app, load_results_path, baseMVA=100):
    loads = {}
    with open(load_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        for row in reader:
            loads[row[idx_of["ind"]]] = {
                "plini": float(row[idx_of["pd"]]) * baseMVA,
                "qlini": float(row[idx_of["qd"]]) * baseMVA,
                "outserv": 0 if row[idx_of["status"]] == "1" else 1,
            }
    return loads


def parse_buses(app, bus_results_path):
    buses = {}
    with open(bus_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        for row in reader:
            buses[row[idx_of["ind"]]] = {
                "vm": float(row[idx_of["vm"]]),
                "va": float(row[idx_of["va"]]),
            }
    return buses


def parse_branches(app, branch_results_path):
    branches = {}
    with open(branch_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        for row in reader:
            tm = float(row[idx_of["tm"]])
            if math.isclose(tm, 0.9, abs_tol=1e-5):
                tm = 0.9
            elif math.isclose(tm, 1.1, abs_tol=1e-5):
                tm = 1.1
            branches[row[idx_of["ind"]]] = {
                "tm": tm,
                "tap_percentage": 100 * (tm - 1),
            }
    return branches


def parse_shunts(app, shunt_results_path):
    shunts = {}
    with open(shunt_results_path, "r") as f:
        reader = csv.reader(f)
        idx_of = header_indexes(next(reader))
        if "shunt_bigM" in idx_of.keys():
            for row in reader:
                shunt_bigM = float(row[idx_of["shunt_bigM"]])
                if math.isclose(shunt_bigM, 0.0, abs_tol=1e-5):
                    shunts[row[idx_of["ind"]]] = {"outserv": 1}
                else:
                    shunts[row[idx_of["ind"]]] = {"outserv": 0}
        elif "outserv" in idx_of.keys():
            for row in reader:
                shunts[row[idx_of["ind"]]] = {"outserv": int(row[idx_of["outserv"]])}
        else:
            raise ValueError("No shunt status found in shunt results file")
    return shunts


def parse_setpoint_from_opf_results(app, opf_results_dir):
    setpoint_data = {}
    setpoint_data["gen"] = parse_gens(app, opf_results_dir / "gen.csv")
    setpoint_data["convdc"] = parse_convs(app, opf_results_dir / "convdc.csv")
    setpoint_data["load"] = parse_loads(app, opf_results_dir / "load.csv")
    setpoint_data["bus"] = parse_buses(app, opf_results_dir / "bus.csv")
    setpoint_data["branch"] = parse_branches(app, opf_results_dir / "branch.csv")
    try:
        setpoint_data["shunt"] = parse_shunts(app, opf_results_dir / "shunt.csv")
    except FileNotFoundError:
        app.PrintInfo("No shunt results found")
        setpoint_data["shunt"] = {}
    return setpoint_data


# makes an operation scenario
def make_operation_scenario(app, operation_scenario_name, target=None):
    # get study case
    if target is None:
        target = app.GetProjectFolder("scen")

    # create operation scenario
    if target.GetContents(f"{operation_scenario_name}.IntScenario") != []:
        for scenario in target.GetContents(f"{operation_scenario_name}.IntScenario"):
            scenario.Deactivate()
            scenario.Delete()

    operation_scenario = target.CreateObject("IntScenario")
    operation_scenario.loc_name = operation_scenario_name
    operation_scenario.Activate()
    return operation_scenario


def apply_setpoint_gens(app, setpoint_data):
    gens = (
        app.GetCalcRelevantObjects("ElmSym")
        + app.GetCalcRelevantObjects("ElmGenstat")
        + app.GetCalcRelevantObjects("ElmPvsys")
    )
    for gen in gens:
        if "conv" not in gen.loc_name:
            pm_index = gen.GetAttribute("desc")[0].replace("PowerModels index: ", "")
            if (
                pm_index in setpoint_data["gen"].keys()
                and setpoint_data["gen"][pm_index]["outserv"] == 0
            ):
                gen.SetAttribute("outserv", 0)
                if gen.GetClassName() != "ElmPvsys":
                    gen.SetAttribute("pgini", setpoint_data["gen"][pm_index]["pgini"])
                    gen.SetAttribute("qgini", setpoint_data["gen"][pm_index]["qgini"])
                else:
                    gen.SetAttribute(
                        "pgini", setpoint_data["gen"][pm_index]["pgini"] * 1000
                    )
                    gen.SetAttribute(
                        "qgini", setpoint_data["gen"][pm_index]["qgini"] * 1000
                    )

                gen_bus = gen.bus1.cterm
                bus_pm_index = gen_bus.GetAttribute("desc")[0].replace(
                    "PowerModels index: ", ""
                )
                gen.SetAttribute("usetp", setpoint_data["bus"][bus_pm_index]["vm"])

            else:
                gen.SetAttribute("outserv", 1)
                gen.SetAttribute("pgini", 0)
                gen.SetAttribute("qgini", 0)


def apply_setpoint_svc(app, setpoint_data):
    svc = app.GetCalcRelevantObjects("ElmSvs")
    for svc in svc:
        pm_index = svc.GetAttribute("desc")[0].replace("PowerModels index: ", "")
        svc.SetAttribute("qsetp", -setpoint_data["gen"][pm_index]["qgini"])


def apply_setpoint_loads(app, setpoint_data):
    loads = app.GetCalcRelevantObjects("ElmLod")
    for load in loads:
        pm_index = load.GetAttribute("desc")[0].replace("PowerModels index: ", "")
        load.SetAttribute("plini", setpoint_data["load"][pm_index]["plini"])
        load.SetAttribute("qlini", setpoint_data["load"][pm_index]["qlini"])
        load.SetAttribute("outserv", setpoint_data["load"][pm_index]["outserv"])


def apply_setpoint_convs(app, setpoint_data):
    convs = [
        gen
        for gen in app.GetCalcRelevantObjects("ElmGenstat")
        if "conv" in gen.loc_name
    ]
    for conv in convs:
        pm_index = conv.GetAttribute("desc")[0].replace("PowerModels index: ", "")
        conv.SetAttribute("pgini", setpoint_data["convdc"][pm_index]["pgini"])
        conv.SetAttribute("qgini", setpoint_data["convdc"][pm_index]["qgini"])

        gen_bus = conv.bus1.cterm
        bus_pm_index = gen_bus.GetAttribute("desc")[0].replace(
            "PowerModels index: ", ""
        )
        conv.SetAttribute("usetp", setpoint_data["bus"][bus_pm_index]["vm"])


def apply_setpoint_branches(app, setpoint_data):
    tr2s = app.GetCalcRelevantObjects("ElmTr2")
    for tr2 in tr2s:
        pm_index = tr2.GetAttribute("desc")[0].replace("PowerModels index: ", "")
        dutap = tr2.typ_id.dutap
        tr2.SetAttribute(
            "nntap", round(setpoint_data["branch"][pm_index]["tap_percentage"] / dutap)
        )
        # modify branch shunts
        if setpoint_data["branch"][pm_index]["tap_percentage"] != 0:
            f_bus_name = tr2.GetAttribute("desc")[1].replace("f_bus: ", "")
            f_bus_shunt = app.GetCalcRelevantObjects(
                f"shunt_{tr2.loc_name}_{f_bus_name}.ElmShnt"
            )
            if f_bus_shunt != []:
                f_bus_shunt = f_bus_shunt[0]
                app.PrintInfo(f"Modifying shunt at {f_bus_name}")
                f_bus_shunt.SetAttribute(
                    "ncapa",
                    round(
                        f_bus_shunt.ncapa
                        / (
                            setpoint_data["branch"][pm_index]["tm"]
                            * setpoint_data["branch"][pm_index]["tm"]
                        ),
                    ),
                )


def apply_setpoint_station_controllers(app, setpoint_data):
    station_controllers = app.GetCalcRelevantObjects("ElmStactrl")
    for station_controller in station_controllers:
        con_bus = station_controller.GetAttribute("rembar")
        bus_pm_index = con_bus.GetAttribute("desc")[0].replace(
            "PowerModels index: ", ""
        )
        station_controller.SetAttribute(
            "usetp", setpoint_data["bus"][bus_pm_index]["vm"]
        )


def apply_setpoint_shunts(app, setpoint_data):
    shunts = app.GetCalcRelevantObjects("ElmShnt")
    for shunt in shunts:
        shunt_pm_index = shunt.GetAttribute("desc")[0].replace(
            "PowerModels index: ", ""
        )
        if shunt_pm_index in setpoint_data["shunt"].keys():
            shunt.SetAttribute(
                "outserv", setpoint_data["shunt"][shunt_pm_index]["outserv"]
            )


def turn_off_isolated_buses_and_connected_elements(
    app,
    isolated_bus_names=[
        "bus_N2",
        "lv_bus_wtg_N2_1",
        "lv_bus_pv_N2_1",
        "bus_N4",
        "lv_bus_wtg_N4_1",
        "lv_bus_pv_N4_1",
        "bus_Q6",
        "lv_bus_wtg_Q6_1",
        "lv_bus_pv_Q6_1",
    ],
):
    for bus_name in isolated_bus_names:
        try:
            bus = app.GetCalcRelevantObjects(f"{bus_name}.ElmTerm")[0]
            bus.SetAttribute("outserv", 1)
            for elm in bus.GetConnectedElements():
                elm.SetAttribute("outserv", 1)
                if elm.HasAttribute("c_pmod"):
                    if elm.c_pmod is not None:
                        elm.c_pmod.SetAttribute("outserv", 1)
                        for dsl in elm.c_pmod.GetContents():
                            dsl.SetAttribute("outserv", 1)
                if elm.HasAttribute("c_pstac"):
                    if elm.c_pstac is not None:
                        elm.c_pstac.SetAttribute("outserv", 1)
        except:
            pass


def apply_setpoint_to_operation_scenario(app, operation_scenario, setpoint_data):
    apply_setpoint_gens(app, setpoint_data)
    apply_setpoint_loads(app, setpoint_data)
    apply_setpoint_convs(app, setpoint_data)
    apply_setpoint_branches(app, setpoint_data)
    apply_setpoint_station_controllers(app, setpoint_data)
    apply_setpoint_shunts(app, setpoint_data)
    apply_setpoint_svc(app, setpoint_data)
    turn_off_isolated_buses_and_connected_elements(app)
    operation_scenario.Save()


def check_if_scenario_has_solved(app, hour_dir):
    # check if scenario has solved
    with open(f"{hour_dir / 'metadata.csv'}", "r") as f:
        reader = csv.reader(f)
        next(reader)
        return next(reader)[1] in ["LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"]


def add_operation_scenarios_for_isp_year(
    app, year_dir, skip_existing=True, target=None, hours=None
):
    # get target folder
    if target is None:
        target = app.GetProjectFolder("scen")

    # get hours
    if hours is None:
        hours = os.listdir(year_dir)

    # make operation scenarios for each hour
    for hour_str in hours:
        # parse hour
        hour = int(hour_str)
        scenario_name = f"hour_{str(hour).zfill(3)}"
        hour_dir = year_dir / hour_str

        # skip unsolved scenarios
        if not check_if_scenario_has_solved(app, hour_dir):
            app.PrintInfo(f"Skipping {scenario_name} because it has not solved")
            continue
        # skip if already exists
        if skip_existing and target.GetContents(f"{scenario_name}.IntScenario") != []:
            app.PrintInfo(f"Skipping {scenario_name}")
            continue

        # parse setpoints
        setpoint_data = parse_setpoint_from_opf_results(app, hour_dir)

        # make scenario
        operation_scenario = make_operation_scenario(app, scenario_name, target=target)

        # apply setpoints
        apply_setpoint_to_operation_scenario(app, operation_scenario, setpoint_data)
