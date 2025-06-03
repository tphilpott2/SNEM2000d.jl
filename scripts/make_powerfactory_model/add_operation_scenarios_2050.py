import os
import sys
import csv
import math
from pathlib import Path
import importlib

import powerfactory

# import applyscenario module
path_nem2000d = Path(__file__).resolve().parents[2]
path_mod = path_nem2000d / "src" / "make_powerfactory_model"

# Remove any existing instances of path_mod from sys.path
if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

# Add the correct path to sys.path
sys.path.insert(0, str(path_mod))

import applyscenario as add_op

importlib.reload(add_op)


# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
# base power
baseMVA = 100

# setpoints directory
setpoints_dir = path_nem2000d / "results" / "opf" / "2050" / "stage_2"

# skip existing scenarios
skip_existing = True

# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------


if __name__ == "__main__":
    app = powerfactory.GetApplication()
    app.ClearOutputWindow()

    # turn off any active variations
    for variation in app.GetActiveNetworkVariations():
        variation.Deactivate()

    # apply operation scenarios for each year
    op_scens = app.GetProjectFolder("scen")
    year = 2050
    # get or create year folder
    if len(op_scens.GetContents(f"{year}_base.IntFolder")) > 0:
        year_folder = op_scens.GetContents(f"{year}_base.IntFolder")[0]
    else:
        year_folder = op_scens.CreateObject("IntFolder")
        year_folder.loc_name = str(year) + "_base"

    # add operation scenarios
    add_op.add_operation_scenarios_for_isp_year(
        app,
        setpoints_dir,
        target=year_folder,
        # hours=["1"],
    )
