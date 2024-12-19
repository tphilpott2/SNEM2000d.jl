import powerfactory


# delete existing networks, study cases and equipment types
def clean_project(app):
    # clean study cases
    study_folder = app.GetProjectFolder("study")
    if len(study_folder.GetContents()) != 0:
        for sc in study_folder.GetContents():
            if sc.GetClassName() == "ComTasks":
                sc.Delete()
                continue
            sc.Deactivate()
            sc.Delete()

    # clean equipment type library
    equip_folder = app.GetProjectFolder("equip")
    if len(equip_folder.GetContents()) != 0:
        for e in equip_folder.GetContents():
            e.Delete()

    # clean networks and diagrams
    netdat_folder = app.GetProjectFolder("netdat")
    dia_folder = app.GetProjectFolder("dia")
    delete_nets = netdat_folder.GetContents("*.ElmNet") + dia_folder.GetContents(
        "*.IntGrfnet"
    )
    if len(delete_nets) != 0:
        for d in delete_nets:
            if d.GetClassName() == "ElmNet":
                d.Deactivate()
            else:
                d.Close()
            d.Delete()

    # clean operation scenarios
    scen_folder = app.GetProjectFolder("scen")
    if len(scen_folder.GetContents()) != 0:
        for s in scen_folder.GetContents():
            s.Delete()


# create study case
def create_study_case(app, study_case_name):
    study_folder = app.GetProjectFolder("study")
    study_case = study_folder.CreateObject("IntCase")
    study_case.loc_name = study_case_name
    study_case.Activate()
    return study_case


# create new network ElmNet object
def create_network(app, network_name, freq):
    netdat_folder = app.GetProjectFolder("netdat")
    net = netdat_folder.CreateObject("ElmNet")
    net.loc_name = f"{network_name}_grid"
    net.SetAttribute("frnom", freq)
    net.Activate()
    return net


# default input options, can be overwritten as input to initialise_project
default_input_options = {
    "OptTyptr2": {"iopt_uk": "rx"},
    "OptElmshnt": {"iorl_": "ind", "ioin_": "des"},
    "OptTyplne": {"ioxl_": "ind"},
}


# configure the input options for the network
def set_input_options(app, input_options):
    # get settings folder
    prj = app.GetActiveProject()
    settings_folder = prj.GetContents("*.SetFold")[0]

    # create input options folder if it doesn't exist
    if len(settings_folder.GetContents("*.IntOpt")) == 0:
        int_opt = settings_folder.CreateObject("IntOpt")
    else:  # delete existing input options
        int_opt = settings_folder.GetContents("*.IntOpt")[0]
        for x in int_opt.GetContents():
            x.Delete()

    # set input options
    for opt, attrs in input_options.items():
        opt_obj = int_opt.CreateObject(opt)
        for attr, val in attrs.items():
            opt_obj.SetAttribute(attr, val)


# delete all existing data in the network
# create new network, study case and equipment types
# set input options
# initialise data dictionary
def prepare_project(
    app,
    data,
    network_name,
    desc=[""],
    freq=50,
    study_case_name="base_case",
    input_options=default_input_options,
):
    # add scenairo to project description
    prj = app.GetActiveProject()
    prj.SetAttribute("desc", desc)

    # delete existing networks, study cases, operation scenarios and equipment types
    clean_project(app)

    # create new study case
    create_study_case(app, study_case_name)

    # create new network
    net = create_network(app, network_name, freq)

    # set input options
    set_input_options(app, input_options)

    # initialise data dictionary
    data["directories"] = {
        "net": net,
        "elib": app.GetProjectFolder("equip"),
    }

    app.PrintInfo("Project initialisation complete")
    return data
