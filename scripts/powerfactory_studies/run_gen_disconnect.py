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


# define hour and gen to disconnect
hour = "015"
gen_name = "gen_3301_1"
# define disconnect time
t_disconnect = 0.1
# get faulted gen
gen = app.GetCalcRelevantObjects(f"{gen_name}.ElmSym")[0]

# define output directory
output_dir = path_nem20000d / "results" / "powerfactory" / "rms_gen_disconnect"


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
    gen_disconnect_results_folder = app.GetFromStudyCase(
        "gen_disconnect_results.IntFolder"
    )

    # run short circuit studies
    case_name = f"gen_disconnect_{gen_name}"

    # configure result file
    res_file = pf.configure_ElmRes(
        app,
        export_data,
        case_name,
        target=gen_disconnect_results_folder,
    )

    # make events file
    events_file = pf.make_IntEvt(app, "gen_disconnect")
    if gen.GetClassName() == "ElmSym":
        pf.make_event_gen_disconnect(app, events_file, gen, t_disconnect)
    else:
        pf.make_event_EvtSwitch(app, events_file, gen, {"time": t_disconnect})
    # quit()
    # run simulation
    pf.run_RMS_simulation(
        app,
        events_file,
        res_file,
        com_inc_parameters={
            "dtgrd": 0.01,
            "iopt_adapt": 0,
        },
        com_sim_parameters={"tstop": 20},
    )

    # plot results
    page = pf.get_page(
        app,
        case_name,
        page_frame="wide_plot",
    )
    plot = pf.make_plot(app, f"speed_{gen_name}_disconnect", page)
    plot.GetDataSeries().SetAttribute("autoSearchResultFile", 0)
    for gen in gens:
        if gen.loc_name != gen_name:
            plot.GetDataSeries().AddCurve(gen, "s:speed", res_file)
    page.DoAutoScale()
    page.Show()
    grb = app.GetGraphicsBoard()
    grb.ZoomAll()

    plot = pf.make_plot(app, f"Psum_{gen_name}_disconnect", page)
    plot.GetDataSeries().SetAttribute("autoSearchResultFile", 0)
    for gen in gens + genstats + pvs:
        if gen.loc_name != gen_name:
            plot.GetDataSeries().AddCurve(gen, "m:Psum:bus1", res_file)
    page.DoAutoScale()
    page.Show()
    grb = app.GetGraphicsBoard()
    grb.ZoomAll()

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
