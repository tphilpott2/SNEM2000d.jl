import sys
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

import isolatesection as iso

importlib.reload(iso)


def pr(x):
    app.PrintInfo(x)


##############################################################
# Definitions and paths
##############################################################
# Scenario name
hour = "76"

base_scenario_name = f"hour_{hour}"

# Path to the powerfactory csv file for terminal results
dir_pf_data_csvs = path_snem2000d / "data" / "SNEM2000d_pf_data"
dir_opf_result_csvs = (
    path_snem2000d / "results" / "opf" / "2050" / "stage_2" / f"{hour}"
)


# defines external source data or powerfactory data
# opf result
# branch_flow_source_type = "opf_result"
# branch_flow_source_path = dir_opf_result_csvs / "branch.csv"
# # powerfactory
branch_flow_source_type = None
branch_flow_source_path = None

#######################################################
# select buses
#######################################################

selected_bus_names = iso.states["QLD"]

# qld_bus_names = [
#     "bus_3563",
#     "bus_3650",
#     "bus_3651",
#     "bus_3652",
#     "bus_3655",
#     "bus_3656",
#     "bus_Q8",
# ]


#######################################################
# Main
#######################################################
if __name__ == "__main__":
    app = powerfactory.GetApplication()
    app.ClearOutputWindow()

    # get network object
    net_fld = app.GetProjectFolder("netdat")
    net = net_fld.GetContents("nem_grid.ElmNet")[0]

    # Run the isolate section
    in_service_elements = iso.run_isolate_section_from_scenario(
        app,
        net,
        selected_bus_names,
        base_scenario_name=base_scenario_name,
        branch_flow_source_type=branch_flow_source_type,
        branch_flow_source_path=branch_flow_source_path,
    )

    # compare load flow
    iso.compare_bus_voltages(
        app,
        selected_bus_names,
        # external_data_type="opf_result",
        # external_data_path=dir_opf_result_csvs,
        base_scenario_name=base_scenario_name,
        u_threshold=1e-6,
    )
