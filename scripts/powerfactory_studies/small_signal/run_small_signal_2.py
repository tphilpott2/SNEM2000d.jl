import os
import csv
import sys
from pathlib import Path
from time import perf_counter
import importlib
import powerfactory

# import pf_utils module
path_nem20000d = Path(__file__).resolve().parents[3]
path_mod = path_nem20000d / "src"

if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

sys.path.insert(0, str(path_mod))

import pf_utils as pf

importlib.reload(pf)

app = powerfactory.GetApplication()

skip_existing = False

# output directory
output_dir = (
    path_nem20000d / "results" / "powerfactory" / "small_signal" / "small_signal_2"
)

nsw_gen_unstable_hours = [
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

tas_gen_unstable_hours = [
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    69,
    70,
    71,
    73,
    74,
    75,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    134,
    135,
    136,
    137,
    138,
    139,
    140,
    141,
    142,
    144,
]

unstable_gen_list_nsw = [
    "gen_1038_1.ElmSym",
    "gen_1039_2.ElmSym",
    "gen_1040_3.ElmSym",
    "gen_1041_4.ElmSym",
    "gen_1042_5.ElmSym",
    "gen_1043_6.ElmSym",
]

unstable_gen_list_tas = [
    "gen_5031_1.ElmSym",
    "gen_5032_2.ElmSym",
    "gen_5033_3.ElmSym",
    "gen_5039_3.ElmSym",
    "gen_5040_4.ElmSym",
    "gen_5041_5.ElmSym",
    "gen_5229_1.ElmSym",
]


def turn_off_PSSs(gen_names):
    # turn off PSS's for selected gens
    for gen_name in gen_names:
        gen = app.GetCalcRelevantObjects(gen_name)[0]
        comp_model = gen.c_pmod
        pss = comp_model.GetAttribute("Pss Slot")
        pss.SetAttribute("outserv", 1)


if __name__ == "__main__":
    app.ClearOutputWindow()

    # get study case folder
    study_case = app.GetActiveStudyCase()

    # configure result file (reused to save memory. results are exported to csv at end of script)
    res_file = app.GetFromStudyCase(f"small_signal.ElmRes")
    res_file.SetAttribute("calTp", 5)
    app.PrintInfo(f"Using result file: {res_file}")

    # get calculation of initial conditions command
    com_inc = app.GetFromStudyCase("ComInc")

    # get operation scenarios folder
    op_scens = app.GetProjectFolder("scen")
    year_folder = op_scens.GetContents("2050_base.IntFolder")[0]

    # create no PSS scenarios folder
    if len(op_scens.GetContents("ss_stage_2.IntFolder")) != 0:
        no_pss_scens_folder = op_scens.GetContents("ss_stage_2.IntFolder")[0]
    else:
        no_pss_scens_folder = op_scens.CreateObject("IntFolder")
        no_pss_scens_folder.loc_name = "ss_stage_2"

    # run for each operation scenario
    for op_scen in year_folder.GetContents():
        interval_name = op_scen.loc_name
        if skip_existing and (output_dir / f"{interval_name}.csv").is_file():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue

        # check if interval is in unstable_hours
        hour_int = int(interval_name.split("_")[1])
        if hour_int not in nsw_gen_unstable_hours + tas_gen_unstable_hours:
            continue

        # create stage 2 scenario
        stage_2_scen = no_pss_scens_folder.AddCopy(op_scen)
        stage_2_scen.loc_name = f"{interval_name}_ss_stage_2"
        stage_2_scen.Activate()

        # turn off PSS's for selected gens
        if hour_int in nsw_gen_unstable_hours:
            turn_off_PSSs(unstable_gen_list_nsw)
        elif hour_int in tas_gen_unstable_hours:
            turn_off_PSSs(unstable_gen_list_tas)
        stage_2_scen.Save()

        # get comMod
        com_mod = app.GetFromStudyCase("comMod")
        com_mod.SetAttribute("ResultFile", res_file)
        com_mod.SetAttribute("isRecUnstabModesOnly", 1)
        com_mod.SetAttribute("iLeft", 1)
        com_mod.SetAttribute("iRight", 1)
        com_mod.SetAttribute("iPart", 1)

        # check that initial conditions are recalculated (this variable wont set for some reason)
        if com_mod.GetAttribute("cinitMode") != 1:
            raise ValueError(f"cinitMode is not 1 - hour {interval_name}")
        com_mod.SetAttribute("pInitCond", com_inc)  # recalculate initial conditions

        # run small signal study
        app.PrintInfo(f"Using comMod: {com_mod}")
        com_mod.Execute()
        pf.export_rms_results(
            app, res_file, output_dir, interval_name
        )  # this should be renamed at some stage. it works with any ElmRes file

        # quit()
