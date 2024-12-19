import powerfactory


def make_cub_and_sw(app, bus, name):
    cub = bus.CreateObject("StaCubic")
    cub.loc_name = f"c_{bus.loc_name}_{name}"
    sw = cub.CreateObject("StaSwitch")
    sw.loc_name = f"sw_{bus.loc_name}_{name}"
    sw.on_off = 1
    return cub, sw


def connect_to_bus(app, elm, bus, connection_attribute="bus1"):
    #  create cubicle
    (cub, sw) = make_cub_and_sw(app, bus, elm.loc_name)
    # connect element and cubicle
    elm.SetAttribute(connection_attribute, cub)
    cub.SetAttribute("obj_id", elm)


def make_type(app, elib, elm_data, elm, type_class):
    #   create type and assign to element
    misc_type = elib.CreateObject(type_class)
    elm.typ_id = misc_type
    misc_type.loc_name = f"t_{elm_data['elm']['loc_name']}"

    #   set attributes
    params = list(elm_data["typ"].keys())
    values = list(elm_data["typ"].values())
    app.DefineTransferAttributes(type_class, ", ".join(params))
    try:
        misc_type.SetAttributes(values)
    except:
        app.PrintInfo(f"Error setting attributes for {misc_type.loc_name}.{type_class}")
        #   so that it actually flags which one is a problem
        for p, v in zip(params, values):
            app.PrintInfo(f"{p} \t {v}")
            misc_type.SetAttribute(p, v)
        quit()
    return misc_type


def make_element(app, target_dir, elm_data, elm_class):
    #   create element
    elm = target_dir.CreateObject(elm_class)

    #   set attributes
    params = list(elm_data["elm"].keys())
    values = list(elm_data["elm"].values())
    app.DefineTransferAttributes(elm_class, ", ".join(params))
    try:
        elm.SetAttributes(values)
    except:
        # try setting desc as a list (this commonly causes issues if the description is to long)
        if "desc" in params:
            elm_data["elm"]["desc"] = list(elm_data["elm"]["desc"])
            values = list(elm_data["elm"].values())
            elm.SetAttributes(values)
        else:  #   iterate so that it actually flags which one is a problem
            app.PrintWarn(
                f"Error setting attributes for {elm_data['elm']['loc_name']}.{elm_class}"
            )
            for p, v in zip(params, values):
                app.PrintInfo(f"{p} \t {v}")
                elm.SetAttribute(p, v)
            quit()
    return elm


def get_station_controller(app, station_controllers, elm_data):
    # check for station controller
    if "stactrl" in elm_data["con"].keys():
        stactrl_name = elm_data["con"]["stactrl"]
        return station_controllers[stactrl_name]["object"]
    else:
        return None
