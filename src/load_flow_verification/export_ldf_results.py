import csv
import powerfactory


def export_ldf_results(app, target_dir, prefix="pf_ldf_results_"):
    # define variables to export
    elm_classes = {
        "ElmTerm": [
            "m:u",
            "m:phiu",
        ],
        "ElmSym": [
            "m:Psum:bus1",
            "m:Qsum:bus1",
        ],
        "ElmGenstat": [
            "m:Psum:bus1",
            "m:Qsum:bus1",
        ],
        "ElmPvsys": [
            "m:Psum:bus1",
            "m:Qsum:bus1",
        ],
    }

    # run load flow
    com_ldf = app.GetFromStudyCase("ComLdf")
    test = com_ldf.Execute()
    if test != 0:
        raise RuntimeError("Load flow failed")

    # export results
    for elm_class, var_list in elm_classes.items():
        with open(
            f"{target_dir}\\{prefix}{elm_class}.csv",
            "w",
            newline="",
        ) as file:
            csvwriter = csv.writer(file)
            header = ["loc_name"] + [var.replace(":", "_") for var in var_list]
            csvwriter.writerow(header)
            for elm in app.GetCalcRelevantObjects(f"*.{elm_class}", 0):
                row = [elm.loc_name]
                for var in var_list:
                    row.append(elm.GetAttribute(var))
                csvwriter.writerow(row)
