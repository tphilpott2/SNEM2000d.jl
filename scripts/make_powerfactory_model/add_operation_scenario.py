import os
import sys
import csv
import math
from pathlib import Path
import importlib

import powerfactory

# import  module
path_snem2000d = Path(__file__).resolve().parents[2]
path_src = path_snem2000d / "src"
if path_src not in sys.path:
    sys.path.append(path_src)

# Remove any existing instances of path_src from sys.path
if str(path_src) in sys.path:
    sys.path.remove(str(path_src))

# Add the correct path to sys.path
sys.path.insert(0, str(path_src))

import applyscenario as app_sc

importlib.reload(app_sc)


# __name__
hour = "1"
hourly_results_dir = (
    path_snem2000d / "results" / "nem2000_uc" / "final" / "stage_2" / "2050" / f"{hour}"
)

if __name__ == "__main__":
    app = powerfactory.GetApplication()
    app.ClearOutputWindow()

    setpoint_data = app_sc.parse_setpoint_from_opf_results(app, hourly_results_dir)

    operation_scenario = app_sc.make_operation_scenario(app, f"hour_{hour}")

    app_sc.apply_setpoint_to_operation_scenario(app, operation_scenario, setpoint_data)
