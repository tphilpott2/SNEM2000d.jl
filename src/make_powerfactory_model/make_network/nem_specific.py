# Functions that are specific to creating the NEM network


# Makes areas for each state
# Appends to data dictionary
def make_nem_areas(app, data):
    # make areas
    area_folder = app.GetDataFolder("ElmArea")
    for area in area_folder.GetContents():
        area.Delete()
    area_folder = app.GetDataFolder("ElmArea", 1)
    area_names = ["NSW", "VIC", "QLD", "SA", "TAS"]
    areas = {}
    for area_name in area_names:
        areas[area_name] = area_folder.CreateObject("ElmArea")
        areas[area_name].loc_name = area_name
    data["areas"] = areas


# retrieves the dynamic models used in the NEM model from the user defined models library
# models must be copied in manually
def get_nem_dynamic_models(app, data):
    # check that nem_dynamic_models folder exists
    user_defined_models_folder = app.GetProjectFolder("blk")
    if len(user_defined_models_folder.GetContents("nem_dynamic_models")) == 0:
        app.PrintInfo(
            "Dynamic models folder not found. Please copy the folder into library |> dynamic models."
        )
        app.PrintInfo(
            "Folder can be found in the nem_dynamic_models project under library |> dynamic models."
        )
        app.PrintInfo(
            "The nem_dynamic_models.pfd file can be found in the 'data' folder of the 'SNEM2000d' repository."
        )
        quit()
    nem_dynamic_models = user_defined_models_folder.GetContents("nem_dynamic_models")[0]

    # get composite model frames
    data["composite_model_frames"] = {
        "SYM Frame_no droop": nem_dynamic_models.GetContents(
            "synchronous_machines\\SYM Frame_no droop.BlkDef"
        )[0],
        "SYM Frame_no droop_torque_reference": nem_dynamic_models.GetContents(
            "synchronous_machines\\SYM Frame_no droop_torque_reference.BlkDef"
        )[0],
        "Frame WECC WT Type 3": nem_dynamic_models.GetContents(
            "WECC_renewable_energy\\Frame WECC WT Type 3.BlkDef"
        )[0],
        "Frame WECC WT Type 4A": nem_dynamic_models.GetContents(
            "WECC_renewable_energy\\Frame WECC WT Type 4A.BlkDef"
        )[0],
        "Frame WECC WT Type 4B": nem_dynamic_models.GetContents(
            "WECC_renewable_energy\\Frame WECC WT Type 4B.BlkDef"
        )[0],
        "Frame WECC Large-scale PV Plant": nem_dynamic_models.GetContents(
            "WECC_renewable_energy\\Frame WECC Large-scale PV Plant.BlkDef"
        )[0],
    }

    data["dsl_model_types"] = {
        # synchronous machine dsls
        "TGOV1": nem_dynamic_models.GetContents("synchronous_machines\\TGOV1.BlkDef")[
            0
        ],
        "HYGOV": nem_dynamic_models.GetContents("synchronous_machines\\HYGOV.BlkDef")[
            0
        ],
        "IEEET1": nem_dynamic_models.GetContents("synchronous_machines\\IEEET1.BlkDef")[
            0
        ],
        "PSS2B": nem_dynamic_models.GetContents("synchronous_machines\\PSS2B.BlkDef")[
            0
        ],
        # wtg dsls
        "WECC_wind_turbine": {
            "WTGTRQ_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\WTGTRQ_A.BlkDef"
            )[0],
            "WTGPT_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\WTGPT_A.BlkDef"
            )[0],
            "WTGAR_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\WTGAR_A.BlkDef"
            )[0],
            "WTGT_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\WTGT_A.BlkDef"
            )[0],
            "REEC_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\REEC_A.BlkDef"
            )[0],
            "REGC_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\REGC_A.BlkDef"
            )[0],
        },
        # pv dsls
        "WECC_pv": {
            "REEC_B": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\REEC_B.BlkDef"
            )[0],
            "REGC_A": nem_dynamic_models.GetContents(
                "WECC_renewable_energy\\REGC_A.BlkDef"
            )[0],
        },
        # vsr dsl
        "VSR": nem_dynamic_models.GetContents(
            "WECC_renewable_energy\\Voltage Source Reference (dq).BlkDef"
        )[0],
    }
