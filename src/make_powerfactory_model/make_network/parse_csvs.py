import csv
from pathlib import Path
import importlib
import powerfactory
from time import perf_counter
import ast


# return key value pairs of header title and index
def header_indexes(header):
    return {val: ind for ind, val in enumerate(header)}


# automatic type conversion based on hierarchical structure.
# attempts to return int, then float, then entry (string)
# applicable in most cases but does need to be adjusted occasionally for specific cases
def parse_row_entry_type(row_entry):
    try:
        return int(row_entry)
    except:
        try:
            return float(row_entry)
        except:
            return row_entry


# parse a row of csv data into a dictionary
def parse_csv_row(row, header):
    # initialize dictionary
    misc_dict = {
        "elm": {},  # element data
        "con": {},  # connection data
        "typ": {},  # type data
        "mat": {},  # matrix entries
        "grf": {},  # graphical data
        "gco": {},  # graphical coordinates
        "msc": {},  # miscellaneous
        "res": {},  # results
    }

    # iterate over each entry in the row and sort
    for idx, param in enumerate(header):
        if row[idx] == "NA":
            continue
        else:
            try:
                param_type = param.split("_")[0]
                misc_dict[param_type][param.replace(f"{param_type}_", "")] = (
                    parse_row_entry_type(row[idx])
                )
            except:
                idx_of = header_indexes(header)

                raise ValueError(
                    f"Parameter {param} not recognized for {row[idx_of['elm_loc_name']]}"
                )

    # results are not used to make network
    del misc_dict["res"]
    # remove empty dictionaries
    for key in list(misc_dict.keys()):
        if len(misc_dict[key].keys()) == 0:
            del misc_dict[key]

    # convert descriptions to a list
    if "desc" in misc_dict["elm"].keys():
        misc_dict["elm"]["desc"] = [
            desc_line for desc_line in misc_dict["elm"]["desc"].split("\n")
        ]

    # convert matrix entries to lists of ints/floats
    if "mat" in misc_dict.keys():
        for matrix_row_index, matrix_row in misc_dict["mat"].items():
            misc_dict["mat"][matrix_row_index] = [
                parse_row_entry_type(entry) for entry in matrix_row.split(",")
            ]

    # convert graphical coordinates to lists of ints/floats
    if "gco" in misc_dict.keys():
        for gco_key, gco_val in misc_dict["gco"].items():
            misc_dict["gco"][gco_key] = ast.literal_eval(gco_val)

    return misc_dict


# parse a csv file of data for elements of a specific class
def parse_csv(app, file_path):
    elm_class_data = {}
    if not file_path.exists():
        app.PrintInfo(f"File {file_path} not found")
    else:
        with open(file_path) as file:
            csvreader = csv.reader(file)
            header = next(csvreader)
            idx_of = header_indexes(header)
            for row in csvreader:
                elm_name = row[idx_of["elm_loc_name"]]
                elm_class_data[elm_name] = parse_csv_row(row, header)

    return elm_class_data


# parse all network data from csv files
def parse_network_from_csvs(app, data, data_dir, prefix="pf_data_"):
    ts = perf_counter()
    # initialise data dict
    data["network"] = {}

    # parse data of all non ELmDsl classes
    dir_path = Path(data_dir)
    data["network"]["ElmTerm"] = parse_csv(app, data_dir / f"{prefix}ElmTerm.csv")
    data["network"]["ElmStactrl"] = parse_csv(app, data_dir / f"{prefix}ElmStactrl.csv")
    data["network"]["ElmLne"] = parse_csv(app, data_dir / f"{prefix}ElmLne.csv")
    data["network"]["ElmTr2"] = parse_csv(app, data_dir / f"{prefix}ElmTr2.csv")
    data["network"]["ElmShnt"] = parse_csv(app, data_dir / f"{prefix}ElmShnt.csv")
    data["network"]["ElmLod"] = parse_csv(app, data_dir / f"{prefix}ElmLod.csv")
    data["network"]["ElmSym"] = parse_csv(app, data_dir / f"{prefix}ElmSym.csv")
    data["network"]["ElmGenstat"] = parse_csv(app, data_dir / f"{prefix}ElmGenstat.csv")
    data["network"]["ElmPvsys"] = parse_csv(app, data_dir / f"{prefix}ElmPvsys.csv")
    data["network"]["ElmSvs"] = parse_csv(app, data_dir / f"{prefix}ElmSvs.csv")

    # parse ElmDsls
    dsls_dir = dir_path / "dsl_csvs"
    for dsl_file_path in dsls_dir.iterdir():
        # get dsl data
        all_dsl_data = parse_csv(app, dsls_dir / dsl_file_path)

        # get connected generator
        for dsl_name, dsl_data in all_dsl_data.items():
            try:
                con_gen_full_name = dsl_data["con"]["gen"]
            except:
                raise ValueError(
                    f"Error parsing {dsl_name}. con_gen not found in dsl data"
                )
            try:
                (con_gen_name, con_gen_class) = con_gen_full_name.split(".")
            except:
                raise ValueError(
                    f"Error parsing {dsl_name}. Generator name and class not parsable from {dsl_data['con']['gen']}"
                )
            try:
                con_gen = data["network"][con_gen_class][con_gen_name]
            except:
                raise ValueError(
                    f"Error parsing {dsl_name}. Generator {con_gen_name}.{con_gen_class} not found in network data"
                )

            # add dsl data to generator dict
            if "dsl" not in con_gen:  # create dsl dict if it doesn't exist
                con_gen["dsl"] = {}

            # parse dsl model type from dsl file name
            dsl_model_type = str(dsl_file_path.name).replace(prefix, "")
            dsl_model_type = dsl_model_type.replace(prefix, "")
            dsl_model_type = dsl_model_type.replace(".csv", "")

            # add dsl data to generator dict
            con_gen["dsl"][dsl_model_type] = dsl_data

    app.PrintInfo(f"got data in: \t\t{round(perf_counter() - ts, 2)}")
