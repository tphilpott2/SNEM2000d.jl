import powerfactory
import importlib

from . import make_base

importlib.reload(make_base)

from .make_base import *


def make_ElmTerm(app, net, bus_data, areas):
    bus_name = bus_data["elm"]["loc_name"]

    #   assign area
    if areas is not None and "cpArea" in bus_data["elm"].keys():
        area_name = bus_data["elm"]["cpArea"]
        try:
            bus_data["elm"]["cpArea"] = areas[area_name]
        except:
            app.PrintInfo(
                f"Area {area_name} not found for {bus_name}. No area will be assigned."
            )
            del bus_data["elm"]["cpArea"]

    #   make bus
    bus = make_element(app, net, bus_data, "ElmTerm")

    return bus


def make_ElmStactrl(app, net, stactrl_data, bus1):
    #   create stactrl
    stactrl = make_element(app, net, stactrl_data, "ElmStactrl")

    #  connect stactrl to bus
    stactrl.SetAttribute("rembar", bus1)

    return stactrl


def make_ElmLne(app, net, elib, elm_data, bus1, bus2):
    #   create line
    name = elm_data["elm"]["loc_name"]
    line = make_element(app, net, elm_data, "ElmLne")

    #   connect line to buses
    connect_to_bus(app, line, bus1, connection_attribute="bus1")
    connect_to_bus(app, line, bus2, connection_attribute="bus2")

    #   create line type
    make_type(app, elib, elm_data, line, "TypLne")

    return line


def make_ElmTr2(app, net, elib, elm_data, buslv, bushv):
    #  attempting to set tap values before type is made will result in tap limits being exceeded
    #  so we store the tap value and delete it from the elm_data
    # temp_elm_data = elm_data.copy()
    if "nntap" in elm_data["elm"].keys():
        nntap = elm_data["elm"]["nntap"]
        del elm_data["elm"]["nntap"]
    else:
        nntap = 0

    #   create tr2
    name = elm_data["elm"]["loc_name"]
    tr2 = make_element(app, net, elm_data, "ElmTr2")

    #   connect tr2 to buses
    connect_to_bus(app, tr2, buslv, connection_attribute="buslv")
    connect_to_bus(app, tr2, bushv, connection_attribute="bushv")

    #   create tr2 type
    make_type(app, elib, elm_data, tr2, "TypTr2")

    #  set tap settings
    tr2.SetAttribute("nntap", nntap)

    return tr2


def make_ElmLod(app, net, elib, elm_data, bus1):
    #   create load
    name = elm_data["elm"]["loc_name"]
    load = make_element(app, net, elm_data, "ElmLod")

    #   connect load to bus
    connect_to_bus(app, load, bus1)

    #   create load type
    if "typ" in elm_data.keys():
        make_type(app, elib, elm_data, load, "TypLod")

    return load


def make_ElmShnt(app, net, elm_data, bus1):
    #   create shunt
    name = elm_data["elm"]["loc_name"]
    shunt = make_element(app, net, elm_data, "ElmShnt")

    #   connect shunt to bus
    connect_to_bus(app, shunt, bus1)

    return shunt


def make_ElmSym(app, target_dir, elib, elm_data, bus1, station_controller):
    name = elm_data["elm"]["loc_name"]

    gen = make_element(app, target_dir, elm_data, "ElmSym")

    #   create gen type
    make_type(app, elib, elm_data, gen, "TypSym")

    #   connect gen to bus
    connect_to_bus(app, gen, bus1)

    # connect to station controller if it exists
    if station_controller is not None:
        gen.SetAttribute("c_pstac", station_controller)

    return gen


def make_ElmGenstat(app, target_dir, elm_data, bus1, station_controller):
    name = elm_data["elm"]["loc_name"]

    gen = make_element(app, target_dir, elm_data, "ElmGenstat")

    #   connect gen to bus
    connect_to_bus(app, gen, bus1)

    # connect to station controller if it exists
    if station_controller is not None:
        gen.SetAttribute("c_pstac", station_controller)

    return gen


def make_ElmPvsys(app, target_dir, elm_data, bus1, station_controller):
    # make ElmPvsys
    gen = make_element(app, target_dir, elm_data, "ElmPvsys")

    #   connect gen to bus
    connect_to_bus(app, gen, bus1)

    # connect to station controller if it exists
    if station_controller is not None:
        gen.SetAttribute("c_pstac", station_controller)

    return gen


def make_ElmSvs(app, net, elm_data, bus1):
    #   create svs
    name = elm_data["elm"]["loc_name"]
    svs = make_element(app, net, elm_data, "ElmSvs")

    #   connect svs to buses
    connect_to_bus(app, svs, bus1, connection_attribute="bus1")
    return svs


def make_ElmComp(app, net, name, frame):
    # make composite model
    comp_model = net.CreateObject("ElmComp")
    comp_model.loc_name = f"comp_model_{name}"
    comp_model.typ_id = frame
    return comp_model


def make_ElmDsl(app, target_dir, elm_data, dsl_model_type):
    #   create dsl
    dsl = target_dir.CreateObject("ElmDsl")
    dsl.typ_id = dsl_model_type

    #  set attributes
    for param, value in elm_data["elm"].items():
        dsl.SetAttribute(param, value)

    # set matrix entries
    if "mat" in elm_data.keys():
        for matrix_row_index, matrix_row in elm_data["mat"].items():
            dsl.SetAttribute(f"matrix:{matrix_row_index}", matrix_row)

    return dsl


def make_StaPqmea(app, target_dir, pq_measuement_data):
    # make pq_measurement
    pq_measurement = make_element(app, target_dir, pq_measuement_data, "StaPqmea")

    return pq_measurement


def make_StaVmea(app, target_dir, v_measuremant_data):
    # make v_measurement
    v_measurement = make_element(app, target_dir, v_measuremant_data, "StaVmea")

    return v_measurement


def make_synchronous_generator(
    app,
    net,
    elib,
    elm_data,
    bus1,
    station_controller,
    frame,
    avr_model,
    gov_model,
    pss_model,
):
    name = elm_data["elm"]["loc_name"]

    # make composite model
    comp_model = make_ElmComp(app, net, name, frame)

    # make ElmSym
    gen = make_ElmSym(app, net, elib, elm_data, bus1, station_controller)

    # make ElmDsls
    avr = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"][elm_data["msc"]["avr"]],
        avr_model,
    )

    gov = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"][elm_data["msc"]["gov"]],
        gov_model,
    )

    pss = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"][elm_data["msc"]["pss"]],
        pss_model,
    )

    comp_model.SetAttribute("pelm", [gen, avr, gov, pss, None, None, None])

    return comp_model


def make_type_3_wtg(
    app,
    net,
    elm_data,
    bus1,
    station_controller,
    frame,
    wtg_dsl_models,
    voltage_source_model=False,
):
    name = elm_data["elm"]["loc_name"]

    # make composite model
    comp_model = make_ElmComp(app, net, name, frame)

    # make ElmGenstat
    gen = make_ElmGenstat(app, net, elm_data, bus1, station_controller)

    # make ElmDsls
    wtgtrq_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["WTGTRQ_A"],
        wtg_dsl_models["WTGTRQ_A"],
    )
    wtgpt_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["WTGPT_A"],
        wtg_dsl_models["WTGPT_A"],
    )
    wtgar_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["WTGAR_A"],
        wtg_dsl_models["WTGAR_A"],
    )
    wtgt_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["WTGT_A"],
        wtg_dsl_models["WTGT_A"],
    )
    reec_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REEC_A"],
        wtg_dsl_models["REEC_A"],
    )
    regc_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REGC_A"],
        wtg_dsl_models["REGC_A"],
    )

    # make voltage source reference if required
    if voltage_source_model == False:
        vsr = None
    else:
        vsr = make_ElmDsl(
            app,
            comp_model,
            elm_data["dsl"]["VSR"],
            voltage_source_model,
        )
        # set gen to use voltage source reference
        gen.SetAttribute("iSimModel", 2)

    # make measurement devices
    pq_measurement_data = {
        "elm": {
            "loc_name": f"pq_meas_{name}",
            "pcubic": gen.bus1,
            "i_mode": 1,
            "i_orient": 1,
            "iAstabint": 1,
        }
    }
    pq_measurement = make_StaPqmea(app, comp_model, pq_measurement_data)
    v_measurement_data = {
        "elm": {
            "loc_name": f"v_meas_{name}",
            "pbusbar": gen.bus1.cterm,
            "iOutput": 0,
            "i_mode": 1,
            "iAstabint": 1,
        }
    }
    v_measurement = make_StaVmea(app, comp_model, v_measurement_data)

    # set slots
    comp_model.SetAttribute(
        "pelm",
        [
            gen,
            wtgtrq_a,
            wtgpt_a,
            wtgar_a,
            wtgt_a,
            reec_a,
            regc_a,
            pq_measurement,
            v_measurement,
            None,
            vsr,
            None,  # plant controller
        ],
    )

    return comp_model


def make_type_4A_wtg(
    app,
    net,
    elm_data,
    bus1,
    station_controller,
    frame,
    wtg_dsl_models,
    voltage_source_model=False,
):
    pass


def make_type_4B_wtg(
    app,
    net,
    elm_data,
    bus1,
    station_controller,
    frame,
    wtg_dsl_models,
    voltage_source_model=False,
):
    name = elm_data["elm"]["loc_name"]

    # make composite model
    comp_model = make_ElmComp(app, net, name, frame)

    # make ElmGenstat
    gen = make_ElmGenstat(app, net, elm_data, bus1, station_controller)

    # make ElmDsls
    reec_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REEC_A"],
        wtg_dsl_models["REEC_A"],
    )
    regc_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REGC_A"],
        wtg_dsl_models["REGC_A"],
    )

    # make voltage source reference if required
    if voltage_source_model == False:
        vsr = None
    else:
        vsr = make_ElmDsl(
            app,
            comp_model,
            elm_data["dsl"]["VSR"],
            voltage_source_model,
        )
        # set gen to use voltage source reference
        gen.SetAttribute("iSimModel", 2)

    # make measurement devices
    pq_measurement_data = {
        "elm": {
            "loc_name": f"pq_meas_{name}",
            "pcubic": gen.bus1,
            "i_mode": 1,
            "i_orient": 1,
            "iAstabint": 1,
        }
    }
    pq_measurement = make_StaPqmea(app, comp_model, pq_measurement_data)
    v_measurement_data = {
        "elm": {
            "loc_name": f"v_meas_{name}",
            "pbusbar": gen.bus1.cterm,
            "iOutput": 0,
            "i_mode": 1,
            "iAstabint": 1,
        }
    }
    v_measurement = make_StaVmea(app, comp_model, v_measurement_data)

    # set slots
    comp_model.SetAttribute(
        "pelm",
        [
            gen,
            reec_a,
            regc_a,
            pq_measurement,
            v_measurement,
            None,
            vsr,
            None,  # plant controller
        ],
    )

    return comp_model


def make_pv_generator(
    app,
    net,
    elm_data,
    bus1,
    station_controller,
    frame,
    pv_dsl_models,
    voltage_source_model=False,
):
    name = elm_data["elm"]["loc_name"]

    # make composite model
    comp_model = make_ElmComp(app, net, name, frame)

    # make ElmPvsys
    gen = make_ElmPvsys(app, net, elm_data, bus1, station_controller)

    # make ElmDsls
    reec_b = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REEC_B"],
        pv_dsl_models["REEC_B"],
    )
    regc_a = make_ElmDsl(
        app,
        comp_model,
        elm_data["dsl"]["REGC_A"],
        pv_dsl_models["REGC_A"],
    )

    # make voltage source reference if required
    if voltage_source_model == False:
        vsr = None
    else:
        vsr = make_ElmDsl(
            app,
            comp_model,
            elm_data["dsl"]["VSR"],
            voltage_source_model,
        )
        # set gen to use voltage source reference
        gen.SetAttribute("iSimModel", 2)

    # make measurement devices
    pq_measurement_data = {
        "elm": {
            "loc_name": f"pq_meas_{name}",
            "pcubic": gen.bus1,
            "i_mode": 1,
            "i_orient": 1,
            "iAstabint": 1,
        }
    }
    pq_measurement = make_StaPqmea(app, comp_model, pq_measurement_data)
    v_measurement_data = {
        "elm": {
            "loc_name": f"v_meas_{name}",
            "pbusbar": gen.bus1.cterm,
            "iOutput": 0,
            "i_mode": 1,
            "iAstabint": 1,
        }
    }
    v_measurement = make_StaVmea(app, comp_model, v_measurement_data)

    # set slots
    comp_model.SetAttribute(
        "pelm",
        [
            gen,
            reec_b,
            regc_a,
            pq_measurement,
            v_measurement,
            None,
            vsr,
            None,
        ],
    )

    return comp_model
