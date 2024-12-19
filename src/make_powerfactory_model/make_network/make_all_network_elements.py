import powerfactory
import importlib
from time import perf_counter

from . import make_single_network_element

importlib.reload(make_single_network_element)

from .make_single_network_element import *


def make_all_ElmTerm(app, data):
    ts = perf_counter()
    #  get areas folder if it exists
    if "areas" in data.keys():
        areas = data["areas"]
    else:
        areas = None

    # make All elements of class ElmTerms
    net = data["directories"]["net"]
    for bus_data in data["network"]["ElmTerm"].values():
        #   bus is added to data dictionary for future reference
        bus_data["object"] = make_ElmTerm(app, net, bus_data, areas)
    app.PrintInfo(
        f"All elements of class ElmTerm made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmStactrl(app, data):
    ts = perf_counter()

    # make All elements of class ElmStactrls
    net = data["directories"]["net"]
    for stactrl_data in data["network"]["ElmStactrl"].values():
        # get connected bus objects
        bus = data["network"]["ElmTerm"][stactrl_data["con"]["bus"]]["object"]

        #   stactrl is added to data dictionary for future reference
        stactrl_data["object"] = make_ElmStactrl(app, net, stactrl_data, bus)
    app.PrintInfo(
        f"All elements of class ElmStactrl made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmLne(app, data):
    ts = perf_counter()
    # get network folder and equipment library
    net = data["directories"]["net"]
    elib = data["directories"]["elib"]
    for elm_data in data["network"]["ElmLne"].values():
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]
        bus2 = data["network"]["ElmTerm"][elm_data["con"]["bus2"]]["object"]
        make_ElmLne(app, net, elib, elm_data, bus1, bus2)
    app.PrintInfo(
        f"All elements of class ElmLne made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmTr2(app, data):
    ts = perf_counter()
    # get network folder and equipment library
    net = data["directories"]["net"]
    elib = data["directories"]["elib"]
    for elm_data in data["network"]["ElmTr2"].values():
        # get connected bus objects
        buslv = data["network"]["ElmTerm"][elm_data["con"]["buslv"]]["object"]
        bushv = data["network"]["ElmTerm"][elm_data["con"]["bushv"]]["object"]
        make_ElmTr2(app, net, elib, elm_data, buslv, bushv)
    app.PrintInfo(
        f"All elements of class ElmTr2 made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmLod(app, data):
    ts = perf_counter()
    # get network folder and equipment library
    net = data["directories"]["net"]
    elib = data["directories"]["elib"]
    for elm_data in data["network"]["ElmLod"].values():
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]
        # make load
        load = make_ElmLod(app, net, elib, elm_data, bus1)
    app.PrintInfo(
        f"All elements of class ElmLod made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmShnt(app, data):
    ts = perf_counter()
    # get network folder
    net = data["directories"]["net"]
    for elm_data in data["network"]["ElmShnt"].values():
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]
        # make shunt
        make_ElmShnt(app, net, elm_data, bus1)
    app.PrintInfo(
        f"All elements of class ElmShnt made in: \t\t{round(perf_counter() - ts, 2)}"
    )


# also makes all controllers connected to the generator
def make_all_ElmSym(app, data):
    ts = perf_counter()
    # get network folder
    net = data["directories"]["net"]
    elib = data["directories"]["elib"]

    for elm_data in data["network"]["ElmSym"].values():
        name = elm_data["elm"]["loc_name"]
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]

        # make synchronous machine models with controls or synchronous condensers
        if elm_data["msc"]["powerfactory_model"] in [
            "thermal_generator",
            "hydro_generator",
        ]:
            make_synchronous_generator(
                app,
                net,
                elib,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
                data["composite_model_frames"][elm_data["msc"]["frame_type"]],
                data["dsl_model_types"][elm_data["msc"]["avr"]],
                data["dsl_model_types"][elm_data["msc"]["gov"]],
                data["dsl_model_types"][elm_data["msc"]["pss"]],
            )
        elif elm_data["msc"]["powerfactory_model"] == "synchronous_condenser":
            # create synchronous condenser
            make_ElmSym(
                app,
                net,
                elib,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
            )
        else:
            raise ValueError(
                f"Error creating ElmSym {name}. powerfactory_model {elm_data['msc']['powerfactory_model']} not recognised"
            )
    app.PrintInfo(
        f"All elements of class ElmSym made in: \t\t{round(perf_counter() - ts, 2)}"
    )


# includes  all wind turbine generators and static generators
def make_all_ElmGenstat(app, data):
    ts = perf_counter()
    # get network folder
    net = data["directories"]["net"]

    for elm_data in data["network"]["ElmGenstat"].values():
        name = elm_data["elm"]["loc_name"]
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]

        # get voltage source reference model if required
        vsr_model = (
            data["dsl_model_types"]["VSR"]
            if elm_data["msc"]["powerfactory_model"].endswith("_vsr")
            else False
        )

        # make wtg models and controllers
        if elm_data["msc"]["powerfactory_model"] in [
            "wind_generator",
            "type_3_wind_generator",
            "type_3_wind_generator_vsr",
        ]:
            make_type_3_wtg(
                app,
                net,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
                data["composite_model_frames"][elm_data["msc"]["frame_type"]],
                data["dsl_model_types"]["WECC_wind_turbine"],
                vsr_model,
            )
        elif elm_data["msc"]["powerfactory_model"] in [
            "type_4A_wind_generator",
            "type_4A_wind_generator_vsr",
        ]:
            make_type_4A_wtg(
                app,
                net,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
                data["composite_model_frames"][elm_data["msc"]["frame_type"]],
                data["dsl_model_types"]["WECC_wind_turbine"],
                vsr_model,
            )
        elif elm_data["msc"]["powerfactory_model"] in [
            "type_4B_wind_generator",
            "type_4B_wind_generator_vsr",
        ]:
            make_type_4B_wtg(
                app,
                net,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
                data["composite_model_frames"][elm_data["msc"]["frame_type"]],
                data["dsl_model_types"]["WECC_wind_turbine"],
                vsr_model,
            )
        elif elm_data["msc"]["powerfactory_model"] == "static_generator":
            # create synchronous condenser
            make_ElmGenstat(
                app,
                net,
                elm_data,
                bus1,
                get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
            )
        else:
            raise ValueError(
                f"Error creating ElmGenstat {name}. powerfactory_model {elm_data['msc']['powerfactory_model']} not recognised"
            )

    app.PrintInfo(
        f"All elements of class ElmGenstat made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmPvsys(app, data):
    ts = perf_counter()
    # get network folder
    net = data["directories"]["net"]

    for elm_data in data["network"]["ElmPvsys"].values():
        name = elm_data["elm"]["loc_name"]
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]

        # get voltage source reference model if required
        vsr_model = (
            data["dsl_model_types"]["VSR"]
            if elm_data["msc"]["powerfactory_model"].endswith("_vsr")
            else False
        )

        # make pv generators
        make_pv_generator(
            app,
            net,
            elm_data,
            bus1,
            get_station_controller(app, data["network"]["ElmStactrl"], elm_data),
            data["composite_model_frames"][elm_data["msc"]["frame_type"]],
            data["dsl_model_types"]["WECC_pv"],
            vsr_model,
        )

    app.PrintInfo(
        f"All elements of class ElmPvsys made in: \t\t{round(perf_counter() - ts, 2)}"
    )


def make_all_ElmSvs(app, data):
    ts = perf_counter()
    # get network folder and equipment library
    net = data["directories"]["net"]
    for elm_data in data["network"]["ElmSvs"].values():
        # get connected bus objects
        bus1 = data["network"]["ElmTerm"][elm_data["con"]["bus1"]]["object"]
        # make load
        make_ElmSvs(app, net, elm_data, bus1)
    app.PrintInfo(
        f"All elements of class ElmSvs made in: \t\t{round(perf_counter() - ts, 2)}"
    )
