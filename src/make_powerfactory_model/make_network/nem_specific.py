from datetime import datetime, timezone, timedelta
import csv

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
    }


# parses date string to UTC timestamp (seconds since 1970-01-01 00:00:00)
# always assumes time is 12:00:00
def parse_to_utc(date_str, format_str="%Y-%m-%d"):
    """
    Parse a date string to UTC timestamp (seconds since 1970-01-01 00:00:00).
    Always assumes time is 12:00:00.

    Args:
        date_str (str): Date string to parse (YYYY-MM-DD)
        format_str (str): Format string for datetime.strptime

    Returns:
        int: Unix timestamp (seconds since epoch)

    Example:
        # Parse a date
        timestamp = parse_to_utc("2024-03-14")

        # Use with NewStage
        scheme.NewStage("Stage1", timestamp, 1)
    """
    try:
        # Parse the string to datetime and set time to noon
        dt = datetime.strptime(date_str, format_str)
        dt = dt.replace(hour=12, minute=0, second=0, tzinfo=timezone.utc)

        # Convert to Unix timestamp (seconds since epoch)
        return int(dt.timestamp())

    except ValueError as e:
        raise ValueError(f"Failed to parse date '{date_str}': {e}")


# reads rez gen capacities from csv file
# should be located in the data folder
def read_rez_gen_capacities(app, path_gen_capacities):
    rez_gen_capacities = {}
    with open(path_gen_capacities, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        idx_of = {val: ind for ind, val in enumerate(header)}
        for row in reader:
            gen_name = row[idx_of["gen_name"]]
            rez_gen_capacities[gen_name] = {}
            for year in range(2025, 2051):
                capacity = float(row[idx_of[str(year)]])
                rez_gen_capacities[gen_name][year] = capacity
    return rez_gen_capacities


# makes variations for each ISP year in the year range
def make_isp_variation(app, path_gen_capacities, year_range=(2026, 2051)):
    # delete existing variations
    variations = app.GetProjectFolder("scheme")
    for variation in variations.GetContents():
        variation.Deactivate()
        variation.Delete()

    # read rez gen capacities
    rez_gen_capacities = read_rez_gen_capacities(app, path_gen_capacities)

    # get rez gens
    rez_wtgs = [
        wtg
        for wtg in app.GetCalcRelevantObjects("*.ElmGenstat")
        if wtg.loc_name.startswith("wtg_")
    ]
    rez_pvs = [
        pv
        for pv in app.GetCalcRelevantObjects("*.ElmPvsys")
        if pv.loc_name.startswith("pv_")
    ]

    # create variation
    isp_scheme = variations.CreateObject("IntScheme")
    isp_scheme.loc_name = "ISPHVDC"

    # create new stage for each year
    for year in range(year_range[0], year_range[1]):
        date_str = f"{year}-01-01"
        stage = isp_scheme.NewStage(
            f"{year}",
            parse_to_utc(date_str),
            1,
        )

        # set rez gen capacities for ISP year
        for wtg in rez_wtgs:
            wtg.SetAttribute("sgn", rez_gen_capacities[wtg.loc_name][year])
        for pv in rez_pvs:
            pv.SetAttribute("sgn", 1000 * rez_gen_capacities[pv.loc_name][year])  # kVA
        app.PrintInfo(f"Created ISP variation for {year}")
