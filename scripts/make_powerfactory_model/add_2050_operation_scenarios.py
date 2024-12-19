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
    op_scens = app.GetProjectFolder("scen")
    for hour_str in os.listdir(setpoints_dir):
        # parse hour
        hour = int(hour_str)
        if hour < 10:
            scenario_name = f"hour_00{hour}"
        elif hour < 100:
            scenario_name = f"hour_0{hour}"
        else:
            scenario_name = f"hour_{hour}"

        # skip if already exists
        if skip_existing and op_scens.GetContents(f"{scenario_name}.IntScenario") != []:
            app.PrintInfo(f"Skipping {scenario_name}")
            continue

        # parse setpoints
        setpoint_data = add_op.parse_setpoint_from_opf_results(
            app, setpoints_dir / str(hour)
        )

        # make scenario
        operation_scenario = add_op.make_operation_scenario(app, scenario_name)

        # apply setpoints
        add_op.apply_setpoint_to_operation_scenario(
            app, operation_scenario, setpoint_data
        )
