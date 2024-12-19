import powerfactory
from pathlib import Path
import csv
import importlib

from . import utils

importlib.reload(utils)

from .utils import *


# configures the ComRes object
def configure_ComRes(app, results_file, com_res_parameters={}, target=None):
    # Get target directory
    if target is None:
        target = app.GetActiveStudyCase()

    # Get and configure ComRes object
    com_res = app.GetFromStudyCase("ComRes")
    com_res.SetAttribute("pResult", results_file)
    set_parameters(com_res, com_res_parameters)
    return com_res


# exports rms results and header files
def export_rms_results(
    app, results_file, output_dir, output_name, comres_target=None, comres_parameters={}
):
    # Configure ComRes
    com_res = configure_ComRes(app, results_file, comres_parameters, comres_target)

    # export header
    set_parameters(
        com_res,
        {
            "iopt_exp": 6,  # export csv
            "iopt_vars": 1,  # export header
            "f_name": str(output_dir / f"header_{output_name}.csv"),
        },
    )
    com_res.Execute()

    # export values
    set_parameters(
        com_res,
        {
            "iopt_vars": 0,  # export values
            "f_name": str(output_dir / f"{output_name}.csv"),
        },
    )
    com_res.Execute()


# exports element parameters
def export_parameters(app, dir_path, export_data, prefix=""):
    for set_name, set_data in export_data.items():
        with open(Path(dir_path) / f"{prefix}{set_name}.csv", "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["loc_name"] + set_data["vars"])
            for elm in set_data["elms"]:
                writer.writerow(
                    [elm.loc_name]
                    + [elm.GetAttribute(param) for param in set_data["vars"]]
                )
