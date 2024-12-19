import powerfactory

app = powerfactory.GetApplication()

app.PrintInfo("Started setting voltage source REZ generators")

voltage_source_gen_names = [
    "pv_N3_1.ElmPvsys",
    "wtg_N5_1.ElmGenstat",
    "wtg_V3_1.ElmGenstat",
    "wtg_V4_1.ElmGenstat",
    "pv_Q8_1.ElmPvsys",
    "wtg_Q8_1.ElmGenstat",
    "wtg_Q9_1.ElmGenstat",
    "wtg_S1_1.ElmGenstat",
    "wtg_S3_1.ElmGenstat",
]

# set model type
voltage_source_gens = [
    app.GetCalcRelevantObjects(name)[0] for name in voltage_source_gen_names
]
for gen in voltage_source_gens:
    gen.SetAttribute("iSimModel", 2)
    print(f"Set {gen} to voltage source")

# turn off controllers in operation scenarios
op_scens = app.GetProjectFolder("scen")
for op_scen in op_scens.GetContents():
    op_scen.Activate()
    for gen in voltage_source_gens:
        comp_model = gen.GetAttribute("c_pmod")
        comp_model.SetAttribute("outserv", 1)
