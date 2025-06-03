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

skip_existing = True

# output directory
output_dir = (
    path_nem20000d / "results" / "powerfactory" / "small_signal" / "small_signal_1"
)

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

    # run for each operation scenario
    op_scens = app.GetProjectFolder("scen")
    year_folder = op_scens.GetContents("2050_base.IntFolder")[0]
    for op_scen in year_folder.GetContents():
        interval_name = op_scen.loc_name

        # skip if already exists
        if skip_existing and (output_dir / f"{interval_name}.csv").is_file():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue

        # activate operation scenario
        op_scen.Activate()

        # get comMod
        com_mod = app.GetFromStudyCase("comMod")
        com_mod.SetAttribute("ResultFile", res_file)
        com_mod.SetAttribute("isRecUnstabModesOnly", 1)
        com_mod.SetAttribute("iLeft", 1)
        com_mod.SetAttribute("iRight", 1)
        com_mod.SetAttribute("iPart", 1)

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
