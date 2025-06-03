import os
import csv
import sys
from pathlib import Path
from time import perf_counter
import math
import importlib
import powerfactory
import pandas as pd

# import pf_utils module
path_nem20000d = Path(__file__).resolve().parents[3]
path_mod = path_nem20000d / "src"

if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

sys.path.insert(0, str(path_mod))

import pf_utils as pf

importlib.reload(pf)

app = powerfactory.GetApplication()

skip_existing = True
remake_op_scens = True

# output directory
output_dir = path_nem20000d / "results" / "powerfactory" / "mainland_lccs_no_FCAS"

# scenarios that are unstable if the PSSs are not turned off
mainland_unstable_scenarios_stage_1 = [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    34,
    35,
    46,
    47,
    48,
    54,
    55,
    61,
    101,
    102,
    110,
    111,
    126,
    127,
    132,
    142,
    143,
    144,
    52,  # Gen 1082 dominant state
    53,  # Gen 1082 dominant state
    99,  # Gen 1002 dominant state
]

# scenarios that are unstable in all instances
unstable_scenarios = [46, 47, 54, 55, 61, 101, 102, 110, 111, 142]


def turn_off_tasmania(app):
    area_folder = app.GetDataFolder("ElmArea")
    tas_area = area_folder.GetContents("TAS.ElmArea")[0]

    # buses
    for bus in tas_area.GetBuses():
        bus.SetAttribute("outserv", 1)

    # generators
    for gen in (
        tas_area.GetObjs("ElmSym")
        + tas_area.GetObjs("ElmGenstat")
        + tas_area.GetObjs("ElmPvsys")
    ):
        gen.SetAttribute("outserv", 1)

        # turn off dynamic models if they exist
        comp_model = gen.GetAttribute("c_pmod")
        if comp_model is not None:
            comp_model.SetAttribute("outserv", 1)
            for dsl in comp_model.GetContents():
                dsl.SetAttribute("outserv", 1)

        # turn off station controllers if they exist
        stac = gen.GetAttribute("c_pstac")
        if stac is not None:
            stac.SetAttribute("outserv", 1)


def remake_operation_scenarios(app):
    op_scens = app.GetProjectFolder("scen")

    # get stage 1 and 2 scenarios
    stage_1_scenarios = op_scens.GetContents("2050_base.IntFolder")[0]
    stage_2_scenarios = op_scens.GetContents("ss_stage_2.IntFolder")[0]

    # create folder
    if len(op_scens.GetContents("mainland_no_FCAS.IntFolder")) != 0:
        scenario_dir = op_scens.GetContents("mainland_no_FCAS.IntFolder")[0]
        for scenario in scenario_dir.GetContents():
            scenario.Deactivate()
            scenario.Delete()
    else:
        scenario_dir = op_scens.CreateObject("IntFolder")
        scenario_dir.loc_name = "mainland_no_FCAS"

    # make operation scenarios with stable configuration
    # also turns off Tasmania for each
    for hour in range(1, 145):
        # skip unstable scenarios
        if hour in unstable_scenarios:
            continue

        # copy from stage 2 if interval was unstable in stage 1
        if hour in mainland_unstable_scenarios_stage_1:
            old_scenario = stage_2_scenarios.GetContents(
                f"hour_{str(hour).zfill(3)}_ss_stage_2"
            )[0]
            new_scenario = scenario_dir.AddCopy(old_scenario)
            new_scenario.loc_name = new_scenario.loc_name.replace("_ss_stage_2", "")
        else:  # otherwise just copy from stage 1
            old_scenario = stage_1_scenarios.GetContents(f"hour_{str(hour).zfill(3)}")[
                0
            ]
            new_scenario = scenario_dir.AddCopy(old_scenario)

        # turn off Tasmania
        new_scenario.Activate()
        turn_off_tasmania(app)
        new_scenario.Save()


def get_lcc_gens(app, n_gens=4):
    # Create lists to store the data
    data = []

    # Loop through generator types and collect data
    for class_name in ["ElmSym", "ElmGenstat", "ElmPvsys"]:
        for gen in app.GetCalcRelevantObjects(f"*.{class_name}", 0):
            # For ElmPvsys, divide pgini by 1000 to convert to MW
            pg_value = (
                gen.GetAttribute("pgini") / 1000
                if class_name == "ElmPvsys"
                else gen.GetAttribute("pgini")
            )

            data.append({"name": gen.loc_name, "class": class_name, "pg": pg_value})

    # Create DataFrame from all collected data at once
    dispatch_df = pd.DataFrame(data)
    dispatch_df = dispatch_df.sort_values("pg", ascending=False)  # sort by pg

    return dispatch_df.head(n_gens)


def configure_result_file(app):
    # configure result file
    gens = app.GetCalcRelevantObjects("*.ElmSym", 0)  # active only
    genstats = app.GetCalcRelevantObjects("*.ElmGenstat", 0)  # active only
    pvs = app.GetCalcRelevantObjects("*.ElmPvsys", 0)  # active only
    export_data = {
        "ElmSym": {
            "elms": gens,
            "vars": [
                "s:fipol",
                "s:speed",
                "s:speed:dt",
                "s:P1",
            ],
        },
        "ElmGenstat": {
            "elms": genstats,
            "vars": ["m:Psum:bus1", "s:fe"],
        },
        "ElmPvsys": {
            "elms": pvs,
            "vars": ["m:Psum:bus1", "s:fe"],
        },
    }
    # make reusable result file
    res_file = pf.configure_ElmRes(app, export_data, f"mainland_no_FCAS")

    return res_file


def pr(x):
    app.PrintInfo(x)


if __name__ == "__main__":
    app.ClearOutputWindow()

    # get study case folder
    study_case = app.GetActiveStudyCase()

    # get calculation of initial conditions command
    com_inc = app.GetFromStudyCase("ComInc")

    # get events file (reused for all simulations)
    events_file = app.GetFromStudyCase("evt_mainland_lccs_no_FCAS.IntEvt")

    # get operation scenarios folder
    if remake_op_scens:
        remake_operation_scenarios(app)
    scenario_dir = app.GetProjectFolder("scen").GetContents(
        "mainland_no_FCAS.IntFolder"
    )[0]
    quit()
    # run small signal analysis
    for op_scen in scenario_dir.GetContents():
        interval_name = op_scen.loc_name
        # skip if already exists
        if skip_existing and (output_dir / f"{interval_name}.csv").is_file():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue

        # activate operation scenario
        op_scen.Activate()

        # find lccs
        lcc_gen_df = get_lcc_gens(app, n_gens=10)

        # run simulation for each of the gens
        for index, row in lcc_gen_df.iterrows():
            # get lcc gen
            lcc_gen = app.GetCalcRelevantObjects(f"{row['name']}.{row['class']}", 0)[0]

            # make LCC contingency event
            events_file.Delete()
            events_file = app.GetFromStudyCase("evt_mainland_lccs_no_FCAS.IntEvt")
            pf.make_event_gen_disconnect(app, events_file, lcc_gen, t_disconnect=0.1)

            # configure result file
            res_file = configure_result_file(app)

            # run simulation
            pf.run_RMS_simulation(
                app,
                events_file,
                res_file,
                com_inc_parameters={
                    "dtgrd": 0.01,
                    "iopt_adapt": 0,
                },
                com_sim_parameters={"tstop": 20},
            )

            # export data
            pf.export_rms_results(
                app,
                res_file,
                output_dir,
                f"{interval_name}-{row['name']}-{math.floor(row['pg'])}MW",
                comres_parameters={
                    "numberPrecisionFixed": 10,
                },
            )
