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

# Remove any existing instances of path_mod from sys.path
if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

# Add the correct path to sys.path
sys.path.insert(0, str(path_mod))

import pf_utils as pf

importlib.reload(pf)

app = powerfactory.GetApplication()

skip_existing = True

output_dir = path_nem20000d / "results" / "powerfactory" / "rms_steady_state"

if __name__ == "__main__":
    app.ClearOutputWindow()

    # make events file
    events_file = pf.make_IntEvt(app, "blank_events")

    # make results folder
    res_folder = app.GetFromStudyCase("steady_state_results.IntFolder")

    # run for each operation scenario
    op_scens = app.GetProjectFolder("scen")
    for op_scen in op_scens.GetContents():
        interval_name = op_scen.loc_name

        # skip if already exists
        if skip_existing and (output_dir / f"{interval_name}.csv").is_file():
            app.PrintInfo(f"Skipping {op_scen.loc_name} because it already exists")
            continue

        # activate operation scenario
        op_scen.Activate()

        # configure result file
        gens = app.GetCalcRelevantObjects("*.ElmSym", 0)  # active only
        genstats = app.GetCalcRelevantObjects("*.ElmGenstat", 0)  # active only
        pvs = app.GetCalcRelevantObjects("*.ElmPvsys", 0)  # active only
        export_data = {
            "ElmSym": {
                "elms": gens,
                "vars": ["s:speed", "s:P1"],
            },
            "ElmGenstat": {
                "elms": genstats,
                "vars": ["s:P1"],
            },
            "ElmPvsys": {
                "elms": pvs,
                "vars": ["s:P1"],
            },
        }
        res_file = pf.configure_ElmRes(
            app, export_data, f"steady_state_{interval_name}", target=res_folder
        )

        # run simulation
        pf.run_RMS_simulation(
            app,
            events_file,
            res_file,
            com_inc_parameters={
                "dtgrd": 0.01,
                "iopt_adapt": 0,
            },
            com_sim_parameters={"tstop": 120},
        )

        # plot results
        page = pf.get_page(app, f"{interval_name}", page_frame="wide_plot")
        plot = pf.make_plot(app, f"gen_speed_{interval_name}", page)
        plot.GetDataSeries().SetAttribute("autoSearchResultFile", 0)
        for gen in gens:
            plot.GetDataSeries().AddCurve(gen, "s:speed", res_file)
        page.DoAutoScale()
        page.Show()

        # export data
        pf.export_rms_results(
            app,
            res_file,
            output_dir,
            f"{interval_name}",
            comres_parameters={
                "numberPrecisionFixed": 12,
            },
        )
        # quit()
