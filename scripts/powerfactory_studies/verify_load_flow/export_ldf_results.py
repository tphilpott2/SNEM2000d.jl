import sys
import os
from pathlib import Path


# import export load flow module
path_nem20000d = Path(__file__).resolve().parents[3]
path_mod = path_nem20000d / "src" / "load_flow_verification"

# Remove any existing instances of path_mod from sys.path
if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

# Add the correct path to sys.path
sys.path.insert(0, str(path_mod))

# import export load flow module
import export_ldf_results as ldf
import powerfactory


skip_existing = True
output_dir = path_nem20000d / "results" / "load_flow_verification"

if __name__ == "__main__":
    app = powerfactory.GetApplication()
    app.ClearOutputWindow()
    # run for each operation scenario
    op_scens = app.GetProjectFolder("scen")
    for op_scen in op_scens.GetContents():
        interval_name = op_scen.loc_name

        # make case directory and skip if already exists
        case_dir = output_dir / interval_name
        if skip_existing and case_dir.is_dir():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue
        elif not case_dir.is_dir():
            os.mkdir(case_dir)

        # activate operation scenario
        op_scen.Activate()

        # run load flow and export results
        ldf.export_ldf_results(
            app,
            case_dir,
        )
