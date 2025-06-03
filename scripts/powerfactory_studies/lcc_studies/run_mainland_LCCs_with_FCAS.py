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
remake_op_scens = False

n_sims = 10  # number of LCCs to be considered
n_tasks = 5  # number of simulations to be run in parallel
evt_file_name = "evt_mainland_lccs"
sim_duration = 20.0

# output directory
output_dir = path_nem20000d / "results" / "powerfactory" / "mainland_lccs_with_FCAS"

# csv of ibgs to provide fcas for each hour
fcas_ibgs_fp = path_nem20000d / "data" / "mainland_fcas_ibgs_2050.csv"

# scenarios to skip
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


def read_fcas_ibgs(fp):
    hourly_fcas_ibgs = {}
    with open(fp, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            hourly_fcas_ibgs[int(row[0])] = []
            for i in range(1, len(row)):
                hourly_fcas_ibgs[int(row[0])].append(row[i])
    return hourly_fcas_ibgs


def find_gens_by_name(app, gen_names):
    gens = []
    for gen_name in gen_names:
        for class_name in ["ElmSym", "ElmGenstat", "ElmPvsys"]:
            gen = app.GetCalcRelevantObjects(f"{gen_name}.{class_name}", 0)
            if len(gen) > 0:
                gens.append(gen[0])
                continue
    return gens


def turn_on_FCAS(app, elms):
    comp_models = []
    for elm in elms:
        comp_model = elm.GetAttribute("c_pmod")
        if comp_model is not None:
            comp_models.append(comp_model)

    repc_frames = [
        comp_model.GetAttribute("Plant Control") for comp_model in comp_models
    ]

    repcs = [frame.GetAttribute("Plant Level Control") for frame in repc_frames]

    for repc in repcs:
        repc.SetAttribute("outserv", 0)


def make_operation_scenarios(app, fcas_ibgs_fp):
    op_scens = app.GetProjectFolder("scen")

    # read ibgs to be used for FCAS
    hourly_fcas_ibgs = read_fcas_ibgs(fcas_ibgs_fp)

    # get no REPC scenarios
    no_REPC_scenarios = op_scens.GetContents("mainland_no_FCAS.IntFolder")[0]

    # create LCC scenario folder
    if len(op_scens.GetContents("mainland_with_FCAS.IntFolder")) != 0:
        scenario_dir = op_scens.GetContents("mainland_with_FCAS.IntFolder")[0]
        for scenario in scenario_dir.GetContents():
            scenario.Deactivate()
            scenario.Delete()
    else:
        scenario_dir = op_scens.CreateObject("IntFolder")
        scenario_dir.loc_name = "mainland_with_FCAS"

    # copy scenarios from no REPC folder and turn on selected REPCs
    for old_scenario in no_REPC_scenarios.GetContents():
        # copy scenario
        new_scenario = scenario_dir.AddCopy(old_scenario)
        new_scenario.Activate()

        # turn on selected REPCs
        hour = int(new_scenario.loc_name.split("_")[1])
        fcas_gens = find_gens_by_name(app, hourly_fcas_ibgs[hour])
        turn_on_FCAS(app, fcas_gens)

        # turn off PSSs for some generators that cause instability
        gens = [
            gen
            for gen in app.GetCalcRelevantObjects("*.ElmSym", 0)
            if gen.loc_name
            in [
                "gen_1068_2",
                "gen_3301_1",
            ]
        ]
        turn_off_pss(app, gens)

        # save
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
                "s:firel",
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
    res_file = pf.configure_ElmRes(app, export_data, f"mainland_with_FCAS")

    return res_file


def pr(x):
    app.PrintInfo(x)


def create_comtask_cases(app, study_folder, net, n_tasks, evt_file_name):
    # create cases and reset old ones
    if len(study_folder.GetContents("comtask_cases.IntFolder")) != 0:
        comtask_cases = study_folder.GetContents("comtask_cases.IntFolder")[0]
        for comtask_case in comtask_cases.GetContents():
            comtask_case.Deactivate()
            comtask_case.Delete()
    else:
        comtask_cases = study_folder.CreateObject("IntFolder")
        comtask_cases.loc_name = "comtask_cases"

    # create and configure each case
    for i in range(n_tasks):
        comtask_case = comtask_cases.CreateObject("IntCase")
        comtask_case.loc_name = f"comtask_{i}"
        comtask_case.Activate()

        # activate network
        net.Activate()

        # create cominc
        com_inc = app.GetFromStudyCase("ComInc")
        com_inc.SetAttribute("iopt_adapt", 0)
        com_inc.SetAttribute("iopt_coiref", 1)
        com_inc.SetAttribute("dtgrd", 0.01)

        # create events file
        app.GetFromStudyCase(f"{evt_file_name}.IntEvt")

        # header file
        com_res_header = comtask_case.CreateObject("ComRes")
        pf.set_parameters(
            com_res_header,
            {
                "loc_name": "header",
                "iopt_exp": 6,
                "iopt_vars": 1,
                "f_name": "null_header.csv",
                "numberPrecisionFixed": 10,
                # "pResult": res_file,
            },
        )
        # values file
        com_res_values = comtask_case.CreateObject("ComRes")
        pf.set_parameters(
            com_res_values,
            {
                "loc_name": "values",
                "iopt_exp": 6,
                "iopt_vars": 0,
                "f_name": "null_values.csv",
                "numberPrecisionFixed": 10,
                # "pResult": res_file,
            },
        )

    return comtask_cases


def turn_off_pss(app, gens):
    for gen in gens:
        comp_model = gen.GetAttribute("c_pmod")
        if comp_model is not None:
            pss = comp_model.GetAttribute("Pss Slot")
            pss.SetAttribute("outserv", 1)


if __name__ == "__main__":
    app.ClearOutputWindow()

    # get base network
    netdat_folder = app.GetProjectFolder("netdat")
    net = netdat_folder.GetContents("*.ElmNet")[0]

    # configure comtask study cases
    study_folder = app.GetProjectFolder("study")
    base_case = study_folder.GetContents("base_case")[0]
    comtask_cases = create_comtask_cases(app, study_folder, net, n_tasks, evt_file_name)

    # configure task automation
    existing_comtasks = study_folder.GetContents("*.ComTasks")
    if len(existing_comtasks) != 0:
        for comtask in existing_comtasks:
            comtask.Delete()
    com_tasks = study_folder.CreateObject("ComTasks")
    com_tasks.loc_name = "Task Automation"

    # get operation scenarios folder
    if remake_op_scens:
        make_operation_scenarios(app, fcas_ibgs_fp)
    scenario_dir = app.GetProjectFolder("scen").GetContents(
        "mainland_with_FCAS.IntFolder"
    )[0]

    # run each operation scenario
    for idx, op_scen in enumerate(scenario_dir.GetContents()):
        pr(f"Running operation scenario {idx}")
        interval_name = op_scen.loc_name

        base_case.Activate()
        op_scen.Activate()

        # find lccs
        lcc_gen_df = get_lcc_gens(app, n_gens=n_sims)
        nrows = lcc_gen_df.shape[0]
        if nrows == 0:
            pr(f"No LCCs found for {interval_name}")
            continue

        # configure comtask cases
        for comtasks_i in range(1 + nrows // n_tasks):
            pr(f"Running comtasks_i: {comtasks_i}")

            # delete existing comtask cases
            for comtask_data in com_tasks.GetContents():
                comtask_data.Delete()

            # create new comtask cases
            for local_i in range(n_tasks):
                # skip cases where n_sims/n_tasks is not an integer
                i = comtasks_i * n_tasks + local_i
                if i >= nrows:
                    break

                # skip cases that have already been run
                case_name = f"{interval_name}-{lcc_gen_df.iloc[i]['name']}-{math.floor(lcc_gen_df.iloc[i]['pg'])}MW"
                if skip_existing and (output_dir / f"{case_name}.csv").is_file():
                    pr(f"Skipping {case_name} because it already exists")
                    continue

                # activate study case
                study_case = comtask_cases.GetContents(f"comtask_{local_i}")[0]
                study_case.Activate()

                # activate current op scen
                op_scen.Activate()

                # get lcc gen
                lcc_gen = app.GetCalcRelevantObjects(
                    f"{lcc_gen_df.iloc[i]['name']}.{lcc_gen_df.iloc[i]['class']}"
                )[0]

                # make LCC contingency event
                events_file = app.GetFromStudyCase("evt_mainland_lccs.IntEvt")
                events_file.Delete()  # clearing it properly seems to cause errors
                events_file = app.GetFromStudyCase("evt_mainland_lccs.IntEvt")
                pf.make_event_gen_disconnect(
                    app, events_file, lcc_gen, t_disconnect=0.1
                )

                # configure result file
                res_file = configure_result_file(app)

                # configure ComLdf
                com_ldf = app.GetFromStudyCase("*.ComLdf")

                # configure ComInc
                com_inc = app.GetFromStudyCase("*.ComInc")
                com_inc.SetAttribute("p_event", events_file)
                com_inc.SetAttribute("p_resvar", res_file)

                # configure ComSim
                com_sim = app.GetFromStudyCase("*.ComSim")
                com_sim.SetAttribute("tstop", sim_duration)

                # configure result export
                com_res_header = app.GetFromStudyCase("header.ComRes")
                com_res_header.SetAttribute(
                    "f_name", str(output_dir / f"header_{case_name}.csv")
                )
                com_res_header.SetAttribute("pResult", res_file)
                com_res_values = app.GetFromStudyCase("values.ComRes")
                com_res_values.SetAttribute(
                    "f_name", str(output_dir / f"{case_name}.csv")
                )
                com_res_values.SetAttribute("pResult", res_file)

                # add to comtasks file
                com_tasks.AppendStudyCase(study_case)
                com_tasks.AppendCommand(com_ldf)
                com_tasks.AppendCommand(com_inc)
                com_tasks.AppendCommand(com_sim)
                com_tasks.AppendCommand(com_res_header)
                com_tasks.AppendCommand(com_res_values)

            if len(com_tasks.GetContents()) != 0:  # occurs with skip existing
                # quit()
                com_tasks.Execute()
        # quit()
