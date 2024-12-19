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
output_dir = path_nem20000d / "results" / "powerfactory" / "rms_short_circuit"

# define fault parameters
hour = "015"
line_name = "branch_782"
t_fault = 0.1
# fault clearing times
t_clear_1 = 0.15
t_clear_2 = 0.31
t_clear_3 = 0.32

if __name__ == "__main__":
    app.ClearOutputWindow()

    # activate operation scenario
    op_scen_folder = app.GetProjectFolder("scen")
    op_scen = op_scen_folder.GetContents(f"hour_{hour}.IntScenario")[0]
    op_scen.Activate()

    # configure result file variables
    gens = app.GetCalcRelevantObjects("*.ElmSym", 0)  # active only
    genstats = app.GetCalcRelevantObjects("*.ElmGenstat", 0)  # active only
    pvs = app.GetCalcRelevantObjects("*.ElmPvsys", 0)  # active only
    export_data = {
        "ElmSym": {
            "elms": gens,
            "vars": [
                "s:speed",
                "m:Psum:bus1",
                "s:fipol",
                "m:I1:bus1",
            ],
        },
        "ElmGenstat": {
            "elms": genstats,
            "vars": [
                "m:Psum:bus1",
                "m:I1:bus1",
            ],
        },
        "ElmPvsys": {
            "elms": pvs,
            "vars": [
                "m:Psum:bus1",
                "m:I1:bus1",
            ],
        },
    }

    # get results folder
    sc_results_folder = app.GetFromStudyCase("short_circuit_results.IntFolder")

    # run short circuit studies
    for t_clear in [t_clear_1, t_clear_2, t_clear_3]:
        case_name = f"short_circuit_{line_name}_tc_{int(t_clear*1000)}ms"

        # configure result file
        res_file = pf.configure_ElmRes(
            app,
            export_data,
            case_name,
            target=sc_results_folder,
        )

        # get faulted line
        line = app.GetCalcRelevantObjects(f"{line_name}.ElmLne")[0]

        # make events file
        events_file = pf.make_IntEvt(app, "short_circuit")
        pf.make_event_short_circuit_and_clearance(
            app, events_file, line, t_fault, t_clear
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
            com_sim_parameters={"tstop": 5},
        )

        # plot results
        page = pf.get_page(
            app,
            case_name,
            page_frame="wide_plot",
        )
        plot = pf.make_plot(app, f"fipol_{line_name}", page)
        plot.GetDataSeries().SetAttribute("autoSearchResultFile", 0)
        for gen in gens:
            plot.GetDataSeries().AddCurve(gen, "s:fipol", res_file)
        page.DoAutoScale()
        page.Show()

        # export data
        pf.export_rms_results(
            app,
            res_file,
            output_dir,
            case_name,
            comres_parameters={
                "numberPrecisionFixed": 12,
            },
        )
