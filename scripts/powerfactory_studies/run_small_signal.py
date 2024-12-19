import os
import csv
import sys
from pathlib import Path
from time import perf_counter
import importlib
import powerfactory

# import pf_utils module
path_nem20000d = Path(__file__).resolve().parents[2]
path_mod = path_nem20000d / "src"

if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

sys.path.insert(0, str(path_mod))

import pf_utils as pf

importlib.reload(pf)

app = powerfactory.GetApplication()

skip_existing = True

# output directory
output_dir = path_nem20000d / "results" / "powerfactory" / "small_signal"

# define unstable scenarios for small signal analysis
# these are determined from inspection of the steady state time domain simulations
unstable_scenarios = [
    "hour_001",
    "hour_034",
    "hour_035",
    "hour_046",
    "hour_047",
    "hour_048",
    "hour_054",
    "hour_055",
    "hour_061",
    "hour_101",
    "hour_102",
    "hour_105",
    "hour_110",
    "hour_111",
    "hour_126",
    "hour_127",
    "hour_128",
    "hour_129",
    "hour_131",
    "hour_132",
    "hour_142",
    "hour_143",
    "hour_144",
]

qld_oscillations = [
    "hour_065",
    "hour_068",
    "hour_069",
    "hour_070",
    "hour_071",
    "hour_072",
    "hour_073",
    "hour_074",
    "hour_075",
    "hour_076",
    "hour_077",
    "hour_078",
    "hour_079",
    "hour_080",
    "hour_081",
    "hour_082",
    "hour_106",
    "hour_107",
    "hour_114",
    "hour_115",
    "hour_116",
    "hour_117",
    "hour_118",
    "hour_119",
    "hour_120",
    "hour_121",
]

tas_unstable = [
    "hour_036",
    "hour_037",
    "hour_038",
    "hour_040",
    "hour_041",
    "hour_042",
    "hour_043",
    "hour_044",
    "hour_045",
    "hour_049",
    "hour_050",
    "hour_051",
    "hour_052",
    "hour_053",
    "hour_054",
    "hour_055",
    "hour_056",
    "hour_057",
    "hour_058",
    "hour_059",
    "hour_060",
    "hour_089",
    "hour_090",
    "hour_097",
    "hour_098",
    "hour_099",
    "hour_100",
    "hour_101",
    "hour_102",
    "hour_103",
    "hour_104",
    "hour_105",
    "hour_106",
    "hour_107",
    "hour_108",
    "hour_135",
    "hour_136",
    "hour_137",
    "hour_138",
    "hour_139",
    "hour_140",
]

if __name__ == "__main__":
    app.ClearOutputWindow()

    # get study case folder
    study_case = app.GetActiveStudyCase()

    # make results folder
    res_folder = app.GetFromStudyCase("small_signal_results.IntFolder")

    # run for each operation scenario
    op_scens = app.GetProjectFolder("scen")
    for op_scen in op_scens.GetContents():
        interval_name = op_scen.loc_name

        # only run for cases with visible QLD oscillations
        if interval_name not in unstable_scenarios + qld_oscillations + tas_unstable:
            continue

        # skip if already exists
        if skip_existing and (output_dir / f"{interval_name}.csv").is_file():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue

        # activate operation scenario
        op_scen.Activate()

        # configure result file
        res_file = app.GetFromStudyCase(f"small_signal_{interval_name}.ElmRes")
        res_file.SetAttribute("calTp", 5)
        res_folder.Move(res_file)  # move to small signal results folder
        app.PrintInfo(f"Using result file: {res_file}")

        # get comMod
        com_mod = app.GetFromStudyCase("comMod")
        com_mod.SetAttribute("ResultFile", res_file)
        com_mod.SetAttribute("isRecUnstabModesOnly", 1)
        com_mod.SetAttribute("iLeft", 0)
        com_mod.SetAttribute("iRight", 0)
        com_mod.SetAttribute("iPart", 1)
        app.PrintInfo(f"Using comMod: {com_mod}")

        # run small signal study
        com_mod.Execute()
        pf.export_rms_results(
            app, res_file, output_dir, interval_name
        )  # this should be renamed at some stage. it works with any ElmRes file
