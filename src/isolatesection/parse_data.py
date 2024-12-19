import csv
import math
import powerfactory
import importlib

from . import core

importlib.reload(core)

from .core import *

###################################################################################
# GET BRANCH FLOWS


# parses branch flow data from the branch flows csv
# csv should have columns: loc_name, f_bus, t_bus, pf, qf, pt, qt
# loc_name: as specified in the powerfactory model
# f_bus, t_bus: names of buses in powerfactory model
# for models sourced from PowerModels, there is a function to create this in synthetic_nem_models/src/write_pm_data_to_csvs
def get_branch_flows_from_csv(app, branches_to_replace, fp_source_branch_flows):
    branch_flows = {}
    # get names of branches to replace
    branches_to_replace_names = [branch[0].loc_name for branch in branches_to_replace]

    # read branch flows
    with open(fp_source_branch_flows) as file:
        csvreader = csv.reader(file)
        # index header
        header = next(csvreader)
        idx_of = header_indexer(header)

        # parse rows
        for row in csvreader:
            if row[idx_of["outserv"]] == "1":  # skip out of service branches
                continue
            elif (
                row[idx_of["loc_name"]] not in branches_to_replace_names
            ):  # skip buses that aren't connected
                continue
            else:
                branch_flows[row[idx_of["loc_name"]]] = {
                    "f_bus": row[idx_of["f_bus"]],
                    "t_bus": row[idx_of["t_bus"]],
                    "pf": float(row[idx_of["pf"]]),
                    "qf": float(row[idx_of["qf"]]),
                    "pt": float(row[idx_of["pt"]]),
                    "qt": float(row[idx_of["qt"]]),
                }
    return branch_flows


# parses branch flows from an opf result csv
# for use with nem_2000_isphvdc operating conditions
def get_branch_flows_from_opf_result_csv(
    app, branches_to_replace, fp_source_branch_flows, Sbase=100
):
    branch_flows = {}
    # get names of branches to replace
    branches_to_replace_names = [branch[0].loc_name for branch in branches_to_replace]

    # read branch flows
    with open(fp_source_branch_flows) as file:
        csvreader = csv.reader(file)
        # index header
        header = next(csvreader)
        idx_of = header_indexer(header)

        # parse rows
        for row in csvreader:
            branch_name = f"branch_{row[idx_of['ind']]}"
            if branch_name not in branches_to_replace_names:
                continue
            else:
                # get branch object
                branch = app.GetCalcRelevantObjects(f"{branch_name}.ElmLne")
                if branch == []:
                    branch = app.GetCalcRelevantObjects(f"{branch_name}.ElmTr2")[0]
                else:
                    branch = branch[0]
                # parse branch data
                f_bus = branch.GetAttribute("desc")[1].replace("f_bus: ", "")
                t_bus = branch.GetAttribute("desc")[2].replace("t_bus: ", "")
                branch_flows[branch.loc_name] = {
                    "f_bus": f_bus,
                    "t_bus": t_bus,
                    "pf": float(row[idx_of["pf"]]) * Sbase,
                    "qf": float(row[idx_of["qf"]]) * Sbase,
                    "pt": float(row[idx_of["pt"]]) * Sbase,
                    "qt": float(row[idx_of["qt"]]) * Sbase,
                }
    return branch_flows


# executes a load flow and makes the branch flow dictionary from the ldf results
def get_branch_flows_from_powerfactory(app, branches_to_replace):
    app.PrintInfo("Getting branch flows from powerfactory")
    # run load flow
    run_load_flow(app)

    # make branch flow dictionary
    branch_flows = {}
    for branch, bus in branches_to_replace:
        if branch.GetClassName() == "ElmTr2":
            branch_flows[branch.loc_name] = {
                "f_bus": branch.buslv.cterm.loc_name,
                "t_bus": branch.bushv.cterm.loc_name,
                "pf": branch.GetAttribute("m:P:buslv"),
                "qf": branch.GetAttribute("m:Q:buslv"),
                "pt": branch.GetAttribute("m:P:bushv"),
                "qt": branch.GetAttribute("m:Q:bushv"),
            }
        elif branch.GetClassName() == "ElmLne":
            branch_flows[branch.loc_name] = {
                "f_bus": branch.bus1.cterm.loc_name,
                "t_bus": branch.bus2.cterm.loc_name,
                "pf": branch.GetAttribute("m:P:bus1"),
                "qf": branch.GetAttribute("m:Q:bus1"),
                "pt": branch.GetAttribute("m:P:bus2"),
                "qt": branch.GetAttribute("m:Q:bus2"),
            }
        else:
            raise RuntimeError(
                f"Branch type not recognised: {branch.loc_name}.{branch.GetClassName()}"
            )
    return branch_flows


###################################################################################
# GET TERMINAL VOLTAGES


# parses bus results from a pf data csv
def parse_bus_results_from_pf_data_csv(
    app, dir_pf_data_csvs, selected_bus_names, prefix="pf_data_"
):
    bus_results = {}
    # read data
    with open(dir_pf_data_csvs / f"{prefix}ElmTerm.csv") as file:
        csvreader = csv.reader(file)
        header = next(csvreader)
        idx_of = header_indexer(header)

        # Check for required columns
        required_columns = ["res_u_pu", "res_phi_rad", "res_phi_deg"]
        for col in required_columns:
            if col not in header and col != "res_phi_deg":
                raise RuntimeError(f"{col} column not found")

        # parse rows
        for row in csvreader:
            if row[idx_of["elm_loc_name"]] in selected_bus_names:
                bus_results[row[idx_of["elm_loc_name"]]] = {
                    "u": float(row[idx_of["res_u_pu"]]),
                }
                if "res_phi_rad" in header:
                    bus_results[row[idx_of["elm_loc_name"]]]["phi"] = (
                        float(row[idx_of["res_phi_rad"]]) * 180 / math.pi
                    )
                else:
                    bus_results[row[idx_of["elm_loc_name"]]]["phi"] = float(
                        row[idx_of["res_phi_deg"]]
                    )
    return bus_results


# parses bus results from an opf result csv (nem_2000_isphvdc operating conditions)
def parse_bus_results_from_opf_result_csv(
    app, dir_opf_result_csvs, selected_bus_names, prefix=""
):
    bus_results_pm_inds = {}
    # read data
    with open(dir_opf_result_csvs / f"{prefix}bus.csv") as file:
        csvreader = csv.reader(file)
        header = next(csvreader)
        idx_of = header_indexer(header)

        # Check for required columns
        required_columns = ["vm", "va"]
        for col in required_columns:
            if col not in header:
                raise RuntimeError(f"{col} column not found")

        # parse rows
        for row in csvreader:
            bus_results_pm_inds[row[idx_of["ind"]]] = {
                "u": float(row[idx_of["vm"]]),
                "phi": float(row[idx_of["va"]]) * 180 / math.pi,
            }

        # convert to powerfactory naming convention
        bus_results = {}
        buses = get_selected_buses(app, selected_bus_names)
        for bus in buses:
            pm_index = bus.GetAttribute("desc")[0].replace("PowerModels index: ", "")
            bus_results[bus.loc_name] = {
                "u": bus_results_pm_inds[pm_index]["u"],
                "phi": bus_results_pm_inds[pm_index]["phi"],
            }

    return bus_results


# runs a load flow and saves bus results to a dictionary
def parse_bus_results_from_powerfactory(app, selected_buses):
    app.PrintInfo("Getting bus results from powerfactory")
    run_load_flow(app)
    bus_results = {}
    for bus in selected_buses:
        bus_results[bus.loc_name] = {
            "u": bus.GetAttribute("m:u"),
            "phi": bus.GetAttribute("m:phiu"),
        }
    return bus_results


###################################################################################
# GET GENERATION DISPATCH


# parses generation dispatch from a pf data csv
def parse_gen_dispatch_from_pf_data_csv(
    app, dir_pf_data_csvs, selected_gens, prefix="pf_data_"
):
    selected_gen_names = [gen.loc_name for gen in selected_gens]
    gen_dispatch = {}
    for gen_class in ["ElmSym", "ElmGenstat", "ElmPvsys"]:
        with open(dir_pf_data_csvs / f"{prefix}{gen_class}.csv") as file:
            csvreader = csv.reader(file)
            header = next(csvreader)
            idx_of = header_indexer(header)

            if "elm_pgini" not in header:
                raise RuntimeError("elm_pgini column not found")
            if "elm_qgini" not in header:
                raise RuntimeError("elm_qgini column not found")

            for row in csvreader:
                if row[idx_of["elm_loc_name"]] in selected_gen_names:
                    if gen_class != "ElmPvsys":
                        gen_dispatch[row[idx_of["elm_loc_name"]]] = {
                            "pg": float(row[idx_of["elm_pgini"]]),
                            "qg": float(row[idx_of["elm_qgini"]]),
                        }
                    else:
                        gen_dispatch[row[idx_of["elm_loc_name"]]] = {
                            "pg": float(row[idx_of["elm_pgini"]]) / 1000,  # to MVA
                            "qg": float(row[idx_of["elm_qgini"]]) / 1000,  # to MVA
                        }
    return gen_dispatch


# executes a load flow and makes the generation dispatch dictionary
def parse_gen_dispatch_from_powerfactory(app, selected_gens):
    gen_dispatch = {}
    for gen in selected_gens:
        gen_dispatch[gen.loc_name] = {
            "pg": gen.GetAttribute("m:P:bus1"),
            "qg": gen.GetAttribute("m:Q:bus1"),
        }
    return gen_dispatch
