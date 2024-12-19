import os
import sys
from pathlib import Path
import importlib
import powerfactory

# import make_network module
path_nem2000d = Path(__file__).resolve().parents[2]
path_mod = path_nem2000d / "src" / "make_powerfactory_model"

# Remove any existing instances of path_mod from sys.path
if str(path_mod) in sys.path:
    sys.path.remove(str(path_mod))

# Add the correct path to sys.path
sys.path.insert(0, str(path_mod))

import make_network as mn

importlib.reload(mn)


# directory of pf data csvs
pf_data_dir = path_nem2000d / "data" / "SNEM2000d_pf_data"


# make network
if __name__ == "__main__":
    app = powerfactory.GetApplication()
    app.ClearOutputWindow()
    data = {}

    # clear project, create network, study case and diagram, configure settings
    app.PrintInfo("Started building network")
    mn.prepare_project(app, data, "nem")

    # read network data
    mn.parse_network_from_csvs(app, data, pf_data_dir)

    # get dynamic models from nem_dynamic_models folder
    mn.get_nem_dynamic_models(app, data)

    # make areas
    mn.make_nem_areas(app, data)

    # make network
    mn.make_all_ElmTerm(app, data)
    mn.make_all_ElmStactrl(app, data)
    mn.make_all_ElmLne(app, data)
    mn.make_all_ElmTr2(app, data)
    mn.make_all_ElmLod(app, data)
    mn.make_all_ElmShnt(app, data)
    mn.make_all_ElmSym(app, data)
    mn.make_all_ElmGenstat(app, data)
    mn.make_all_ElmPvsys(app, data)
    mn.make_all_ElmSvs(app, data)

    # make network diagram
    mn.make_network_diagram(app, data, "nem_diagram", page_size=(31233, 62348))
