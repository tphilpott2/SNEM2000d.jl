import powerfactory


# sets parameters for a PowerFactory object
# dict format: {"parameter_name": "value"}
def set_parameters(obj, parameter_dict):
    for param, value in parameter_dict.items():
        obj.SetAttribute(param, value)


# create study case
def make_study_case(app, study_case_name, target=None):
    # get target
    if target is None:
        target = app.GetProjectFolder("study")

    # delete existing study case if it exists
    if target.GetContents(f"{study_case_name}.IntCase") is not []:
        study_case = target.GetContents(f"{study_case_name}.IntCase")[0]
        study_case.Deactivate()
        study_case.Delete()

    # create study case
    study_case = target.CreateObject("IntCase")
    study_case.loc_name = study_case_name
    study_case.Activate()
    return study_case


def run_load_flow(app, throw=True):
    comldf = app.GetFromStudyCase("ComLdf")
    ldf_result = comldf.Execute()
    if throw:
        raise Exception("Load flow failed")
    return ldf_result
