"""
OPF formulation with soft constraints for
     - Nodal power balance in AC and DC
     - Transformer tap limits (if branch["soft_tm"] == true)
"""

function run_uc_oltc_switched_shunt(data, model_constructor, solver; kwargs...)
    return _PM.solve_model(
        data, model_constructor, solver, build_uc_oltc_switched_shunt;
        ref_extensions=
        [
            _PM.ref_add_on_off_va_bounds!, _PMACDC.add_ref_dcgrid!, ref_switched_shunt!
        ],
        multinetwork=false,
        kwargs...
    )
end

function build_uc_oltc_switched_shunt(pm::_PM.AbstractPowerModel)

    _PM.variable_bus_voltage(pm, nw=0)
    _PM.variable_gen_power_on_off(pm, nw=0)
    _PM.variable_branch_power(pm, nw=0)
    _PM.variable_branch_transform(pm, nw=0)
    _PM.constraint_model_voltage(pm, nw=0)

    _PMACDC.variable_active_dcbranch_flow(pm, nw=0)
    _PMACDC.variable_dcbranch_current(pm, nw=0)
    _PMACDC.variable_dc_converter(pm, nw=0)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm, nw=0)
    _PMACDC.constraint_voltage_dc(pm, nw=0)

    # bigM variables
    variable_switched_shunt_bigM(pm, nw=0)
    variable_generator_state(pm, nw=0)

    # constraints
    for i in _PM.ids(pm, nw=0, :ref_buses)
        _PM.constraint_theta_ref(pm, i, nw=0)
    end

    for i in _PM.ids(pm, nw=0, :bus)
        constraint_power_balance_ac_switched_shunt(pm, i, nw=0)
    end

    for i in _PM.ids(pm, nw=0, :gen)
        constraint_generator_on_off(pm, i; nw=0)
    end

    for i in _PM.ids(pm, nw=0, :branch)
        _PM.constraint_ohms_y_oltc_pst_from(pm, i, nw=0)
        _PM.constraint_ohms_y_oltc_pst_to(pm, i, nw=0)
        _PM.constraint_voltage_angle_difference(pm, i, nw=0)
        _PM.constraint_thermal_limit_from(pm, i, nw=0)
        _PM.constraint_thermal_limit_to(pm, i, nw=0)
    end

    for i in _PM.ids(pm, nw=0, :busdc)
        _PMACDC.constraint_power_balance_dc(pm, i, nw=0)
    end

    for i in _PM.ids(pm, nw=0, :branchdc)
        _PMACDC.constraint_ohms_dc_branch(pm, i, nw=0)
    end

    for i in _PM.ids(pm, nw=0, :convdc)
        _PMACDC.constraint_converter_losses(pm, i, nw=0)
        _PMACDC.constraint_conv_transformer(pm, i, nw=0)
        _PMACDC.constraint_conv_reactor(pm, i, nw=0)
        _PMACDC.constraint_conv_filter(pm, i, nw=0)
        _PMACDC.constraint_converter_current(pm, i, nw=0)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i, nw=0)
        end
    end

    objective_oltc_switched_shunt(pm)
end

function objective_oltc_switched_shunt(pm::_PM.AbstractPowerModel; report::Bool=true)
    gen_cost = Dict()
    for (n, nw_ref) in _PM.nws(pm)
        for (i, gen) in nw_ref[:gen]
            pg = sum(_PM.var(pm, n, :pg, i)[c] for c in _PM.conductor_ids(pm, n))

            if length(gen["cost"]) == 1
                gen_cost[(n, i)] = gen["cost"][1]
            elseif length(gen["cost"]) == 2
                gen_cost[(n, i)] = gen["cost"][1] * pg + gen["cost"][2]
            elseif length(gen["cost"]) == 3
                gen_cost[(n, i)] = gen["cost"][1] * pg^2 + gen["cost"][2] * pg + gen["cost"][3]
            else
                gen_cost[(n, i)] = 0.0
            end

        end
    end

    get_soft_branch_indexes(pm, nw) = [i for i in _PM.ids(pm, nw, :branch) if _PM.ref(pm, nw, :branch, i)["soft_tm"] == true]

    soft_costs = pm.data["soft_var_costs"]

    return JuMP.@objective(pm.model, Min,
        sum(
            sum(gen_cost[(0, i)] for (i, gen) in _PM.ref(pm, 0, :gen))) +
        sum(
            soft_costs["alpha_g"] * _PM.var(pm, 0, :alpha_g, i) * (1 - _PM.var(pm, 0, :alpha_g, i))
            for i in _PM.ids(pm, 0, :gen)) +
        sum(
            soft_costs["shunt_bigM"] * _PM.var(pm, 0, :shunt_bigM, i) * (1 - _PM.var(pm, 0, :shunt_bigM, i))
            for i in _PM.ids(pm, 0, :shunt_switched)) +
        sum(
            soft_costs["vm_cost"] * (1 - _PM.var(pm, 0, :vm, i))^2
            for i in _PM.ids(pm, 0, :bus))
    )
end
