import powerfactory


# configures the ElmRes file with the elements and variables defined in export_data
# example export_data format:
# export_data = {
#     "ElmTerm": {
#         "elms": app.GetCalcRelevantObjects("*.ElmTerm", 0),
#         "vars": ["m:u1", "m:phiu"],
#     },
#     "ElmLod": {
#         "elms": app.GetCalcRelevantObjects("*.ElmLod", 0),
#         "vars": ["m:Psum:bus1", "m:Qsum:bus1"],
#     },
# }
def configure_ElmRes(app, export_data, results_file_name, target=None):
    # Get target directory
    if target is None:
        target = app.GetActiveStudyCase()
    # Delete if file exists
    results_file_search = target.GetContents(f"{results_file_name}.ElmRes")
    if results_file_search != []:
        results_file = results_file_search[0]
        results_file.Delete()
    # Create results file
    results_file = target.CreateObject("ElmRes")
    results_file.loc_name = results_file_name

    # add result variables from export_data
    for set_name, set_data in export_data.items():
        for elm in set_data["elms"]:
            for var in set_data["vars"]:
                results_file.AddVariable(elm, var)
        app.PrintInfo(
            f"Added {len(set_data['vars'])} variables for {len(set_data['elms'])} elements in set {set_name}"
        )

    return results_file


# creates or gets the IntEvt file
def make_IntEvt(app, events_file_name, target=None):
    # Get target directory
    if target is None:
        target = app.GetActiveStudyCase()
    # Get or create events file
    events_file_search = target.GetContents(f"{events_file_name}.IntEvt")
    if events_file_search != []:
        events_file = events_file_search[0]
        events_file.Delete()
    # Create events file
    events_file = target.CreateObject("IntEvt")
    events_file.loc_name = events_file_name
    # Clear existing contents
    for event in events_file.GetContents():
        event.Delete()

    return events_file


# makes load step event
def make_event_EvtLod(app, events_file, load, event_parameters, event_name=None):
    # Create event
    event = events_file.CreateObject("EvtLod")
    if event_name is not None:
        event.loc_name = event_name
    else:
        event.loc_name = f"Load Event - {load.loc_name}"

    # Set load
    event.SetAttribute("p_target", load)

    # Set event parameters
    for param, value in event_parameters.items():
        event.SetAttribute(param, value)
    return event


# makes short circuit event
def make_event_EvtShc(app, events_file, bus, event_parameters, event_name=None):
    event = events_file.CreateObject("EvtShc")
    if event_name is not None:
        event.loc_name = event_name
    else:
        event.loc_name = f"Short Circuit Event - {bus.loc_name}"

    # Set bus
    event.SetAttribute("p_target", bus)

    # Set event parameters
    for param, value in event_parameters.items():
        event.SetAttribute(param, value)

    return event


# makes short circuit and clearance event
def make_event_short_circuit_and_clearance(app, events_file, bus, t_fault, t_clear):
    # Make short circuit event
    make_event_EvtShc(
        app,
        events_file,
        bus,
        {
            "time": t_fault,
            "i_shc": 0,  # 3 phase short circuit
        },
        f"Short Circuit - {bus.loc_name}",
    )
    # Make clearance event
    make_event_EvtShc(
        app,
        events_file,
        bus,
        {
            "time": t_clear,
            "i_shc": 4,  # clear 3 phase short circuit
        },
        f"Short Circuit Clearance - {bus.loc_name}",
    )


# makes short circuit event
def make_event_EvtSwitch(
    app, events_file, elm, event_parameters={}, action="open", event_name=None
):
    event = events_file.CreateObject("EvtSwitch")
    if event_name is not None:
        event.loc_name = event_name
    else:
        event.loc_name = f"Switch Event - {elm.loc_name}"

    # Set bus
    event.SetAttribute("p_target", elm)

    # Set switch state
    if action == "close":
        event_parameters["i_switch"] = 1
    elif action == "open":
        event_parameters["i_switch"] = 0
    else:
        raise ValueError(f"Invalid action for switch event: {action}")

    # Set event parameters
    for param, value in event_parameters.items():
        event.SetAttribute(param, value)

    return event


# makes synchronous machine event
def make_event_EvtSym(
    app, events_file, gen, add_trq, event_parameters, event_name=None
):
    event = events_file.CreateObject("EvtSym")
    if event_name is not None:
        event.loc_name = event_name
    else:
        event.loc_name = f"Synchronous Machine Event - {gen.loc_name}"

    # Set bus
    event.SetAttribute("p_target", gen)

    # Set additional torque
    event.SetAttribute("addmt", add_trq)

    # Set event parameters
    for param, value in event_parameters.items():
        event.SetAttribute(param, value)

    return event


# makes generator disconnect event
def make_event_gen_disconnect(app, events_file, gen, t_disconnect):
    # make switch event
    make_event_EvtSwitch(app, events_file, gen, {"time": t_disconnect})
    if gen.GetClassName() == "ElmSym":
        # set gen torque to 0 so that it doesnt crash the simulation
        make_event_EvtSym(app, events_file, gen, -1, {"time": t_disconnect + 0.01})


# configures the ComInc and ComSim objects to run RMS simulation, then runs it
def run_RMS_simulation(
    app,
    events_file,
    results_file,
    com_inc_parameters={},
    com_sim_parameters={"tstop": 10},
):

    # configure ComInc
    com_inc = app.GetFromStudyCase("*.ComInc")
    com_inc.SetAttribute("p_event", events_file)
    com_inc.SetAttribute("p_resvar", results_file)
    for param, value in com_inc_parameters.items():
        com_inc.SetAttribute(param, value)

    # configure ComSim
    com_sim = app.GetFromStudyCase("*.ComSim")
    for param, value in com_sim_parameters.items():
        com_sim.SetAttribute(param, value)

    # Calculate initial conditions and run simulation
    com_ldf = app.GetFromStudyCase("*.ComLdf")
    if com_ldf.Execute() != 0:
        raise Exception("ComLdf failed")
    com_inc.Execute()
    com_sim.Execute()
