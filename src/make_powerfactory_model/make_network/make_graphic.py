import powerfactory
from time import perf_counter


# makes page_name if it doesn't exist
def make_page_size(app, page_name, page_size):
    prj = app.GetActiveProject()
    settings_folder = prj.GetContents("*.SetFold")[0]
    try:  # create drawing formats folder if it doesn't exist
        drawing_formats = settings_folder.GetContents("*.SetFoldPage", 1)[0]
    except:
        drawing_formats = settings_folder.CreateObject("SetFoldPage")

    if (
        drawing_formats.GetContents(page_name) == []
    ):  # create new page size if it doesn't exist
        grid_page_format = drawing_formats.CreateObject("SetFormat")
        grid_page_format.SetAttribute("loc_name", page_name)
        grid_page_format.SetAttribute("iSizeX", page_size[0])
        grid_page_format.SetAttribute("iSizeY", page_size[1])
    elif (
        page_size is not None
    ):  # check if specified page size is different from existing
        grid_page_format = drawing_formats.GetContents(page_name)[0]
        if (
            grid_page_format.GetAttribute("iSizeX") != page_size[0]
            or grid_page_format.GetAttribute("iSizeY") != page_size[1]
        ):
            app.PrintWarn(
                f"Page size {page_name} already exists and is different from the one provided"
            )
            app.PrintWarn(
                f"Existing page size: {grid_page_format.GetAttribute('iSizeX')} x {grid_page_format.GetAttribute('iSizeY')}"
            )
            app.PrintWarn(f"Provided page size: {page_size[0]} x {page_size[1]}")


# make and configure the IntGrfNet object
def make_IntGrfNet(app, data, page_name):
    # get network folder
    net = data["directories"]["net"]

    # create new diagram
    dia_folder = app.GetProjectFolder("dia")
    dig = dia_folder.CreateObject("IntGrfnet")
    dig.loc_name = f"{net.loc_name}_diagram"
    dig.Show()  # opening the diagram creates the settings folder and Format folder

    # set drawing format (page size)
    dig_settings = dig.GetContents("Settings")[0]
    dig_settings.GetContents("Format")[0].aDrwFrm = page_name

    # connect network and diagram
    net.SetAttribute("pDiagram", dig)
    dig.SetAttribute("pDataFolder", net)

    # activate network and close diagram
    net.Activate()
    dig.Close()

    # add dig to data dictionary
    data["directories"]["dig"] = dig

    return dig


# make IntGrf object for element, set attributes and connect element
def make_IntGrf(app, target_dir, elm_data, elm):
    # make IntGrf
    grf = target_dir.CreateObject("IntGrf")
    grf.loc_name = f"grf_{elm_data['elm']['loc_name']}"

    # connect to element
    grf.SetAttribute("pDataObj", elm)

    # set attributes
    params = list(elm_data["grf"].keys())
    values = list(elm_data["grf"].values())
    app.DefineTransferAttributes("IntGrf", ", ".join(params))
    try:
        grf.SetAttributes(values)
    except:
        #   iterate so that it actually flags which one is a problem
        app.PrintWarn(
            f"Error setting attributes for {elm_data['grf']['loc_name']}.{elm_class}"
        )
        for p, v in zip(params, values):
            app.PrintInfo(f"{p} \t {v}")
            grf.SetAttribute(p, v)
        quit()

    return grf


# Legacy code for IntGrfcon. The commented out version worked for PowerFactory 2022 but doesnt work for 2025

# # entries of IntGrfcon.rX and IntGrfcon.rY must be of length 20
# # i dont think theres an easier way to input them
# def pad_gco_entry(app, input_list):
#     # input_list.extend([-1] * (20 - len(input_list)))
#     return input_list


# # make IntGrfcon object for graphic coordinates
# # object is placed inside IntGrf object
# def make_IntGrfcon(app, grf, rX, rY, gco_name="GCO_1"):
#     gco = grf.CreateObject("IntGrfcon")
#     gco.loc_name = gco_name
#     gco.rX = pad_gco_entry(app, rX)
#     gco.rY = pad_gco_entry(app, rY)
#     return gco


# make IntGrfcon object for graphic coordinates
# object is placed inside IntGrf object
def make_IntGrfcon(app, grf, rX, rY, gco_name="GCO_1"):
    gco = grf.CreateObject("IntGrfcon")
    gco.loc_name = gco_name
    for i in range(len(rX)):
        gco.SetAttribute(f"points:{i}", [rX[i], rY[i]])
    return gco


# make all grfs for ElmTerm objects
def make_all_grfs_ElmTerm(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmTerm objects
    # can iterate over data directly as ElmTerm objects are stored
    for bus_data in data["network"]["ElmTerm"].values():
        make_IntGrf(app, dig, bus_data, bus_data["object"])


# make all grfs for ElmSym objects
def make_all_grfs_ElmSym(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmSym objects
    for gen in app.GetCalcRelevantObjects("*.ElmSym"):
        # make IntGrf for ElmSym
        gen_data = data["network"]["ElmSym"][gen.loc_name]
        grf = make_IntGrf(app, dig, gen_data, gen)
        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, gen_data["gco"]["rX"], gen_data["gco"]["rY"])


# make all grfs for ElmGenstat objects
def make_all_grfs_ElmGenstat(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmGenstat objects
    for gen in app.GetCalcRelevantObjects("*.ElmGenstat"):
        # make IntGrf for ElmGenstat
        gen_data = data["network"]["ElmGenstat"][gen.loc_name]
        grf = make_IntGrf(app, dig, gen_data, gen)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, gen_data["gco"]["rX"], gen_data["gco"]["rY"])


# make all grfs for ElmPvsys objects
def make_all_grfs_ElmPvsys(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmPvsys objects
    for gen in app.GetCalcRelevantObjects("*.ElmPvsys"):
        # make IntGrf for ElmPvsys
        gen_data = data["network"]["ElmPvsys"][gen.loc_name]
        grf = make_IntGrf(app, dig, gen_data, gen)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, gen_data["gco"]["rX"], gen_data["gco"]["rY"])


# make all grfs for ElmSvs objects
def make_all_grfs_ElmSvs(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmSvs objects
    for svs in app.GetCalcRelevantObjects("*.ElmSvs"):
        # make IntGrf for ElmSvs
        svs_data = data["network"]["ElmSvs"][svs.loc_name]
        grf = make_IntGrf(app, dig, svs_data, svs)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, svs_data["gco"]["rX"], svs_data["gco"]["rY"])


# make all grfs for ElmLod objects
def make_all_grfs_ElmLod(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmLod objects
    for load in app.GetCalcRelevantObjects("*.ElmLod"):
        # make IntGrf for ElmLod
        load_data = data["network"]["ElmLod"][load.loc_name]
        grf = make_IntGrf(app, dig, load_data, load)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, load_data["gco"]["rX"], load_data["gco"]["rY"])


# make all grfs for ElmShnt objects
def make_all_grfs_ElmShnt(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmShnt objects
    for shunt in app.GetCalcRelevantObjects("*.ElmShnt"):
        # make IntGrf for ElmShnt
        shunt_data = data["network"]["ElmShnt"][shunt.loc_name]
        grf = make_IntGrf(app, dig, shunt_data, shunt)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(app, grf, shunt_data["gco"]["rX"], shunt_data["gco"]["rY"])


# make all grfs for ElmLne objects
def make_all_grfs_ElmLne(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmLne objects
    for line in app.GetCalcRelevantObjects("*.ElmLne"):
        # make IntGrf for ElmLne
        line_data = data["network"]["ElmLne"][line.loc_name]
        grf = make_IntGrf(app, dig, line_data, line)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(
            app,
            grf,
            line_data["gco"]["1_rX"],
            line_data["gco"]["1_rY"],
            gco_name="GCO_1",
        )
        make_IntGrfcon(
            app,
            grf,
            line_data["gco"]["2_rX"],
            line_data["gco"]["2_rY"],
            gco_name="GCO_2",
        )


# make all grfs for ElmTr2 objects
def make_all_grfs_ElmTr2(app, data):
    # get diagram folder
    dig = data["directories"]["dig"]

    # make grfs for all ElmTr2 objects
    for tr2 in app.GetCalcRelevantObjects("*.ElmTr2"):
        # make IntGrf for ElmTr2
        tr2_data = data["network"]["ElmTr2"][tr2.loc_name]
        grf = make_IntGrf(app, dig, tr2_data, tr2)

        # make graphic coordinate object (GCO (i think thats what it stands for))
        make_IntGrfcon(
            app,
            grf,
            tr2_data["gco"]["1_rX"],
            tr2_data["gco"]["1_rY"],
            gco_name="GCO_1",
        )
        make_IntGrfcon(
            app,
            grf,
            tr2_data["gco"]["2_rX"],
            tr2_data["gco"]["2_rY"],
            gco_name="GCO_2",
        )


# make network diagram, including page size, IntGrfNet, and all IntGrf objects
def make_network_diagram(app, data, page_name, page_size=None):
    ts = perf_counter()
    # make page format for diagram if it doesn't exist
    if page_size is not None:
        make_page_size(app, page_name, page_size)

    # make and configure the IntGrfNet object
    dig = make_IntGrfNet(app, data, page_name)

    # make grfs for all objects
    make_all_grfs_ElmTerm(app, data)
    make_all_grfs_ElmSym(app, data)
    make_all_grfs_ElmGenstat(app, data)
    make_all_grfs_ElmPvsys(app, data)
    make_all_grfs_ElmSvs(app, data)
    make_all_grfs_ElmLod(app, data)
    make_all_grfs_ElmShnt(app, data)
    make_all_grfs_ElmLne(app, data)
    make_all_grfs_ElmTr2(app, data)

    # open diagram
    dig.Show()

    app.PrintInfo(f"Network diagram made in: {round(perf_counter() - ts, 2)}s")
