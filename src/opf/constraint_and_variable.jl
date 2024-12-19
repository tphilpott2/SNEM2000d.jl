##########################################################################
# Power balance constraints
##########################################################################

function constraint_power_balance_ac_switched_shunt(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)

    bus_shunts_fixed = _PM.ref(pm, nw, :bus_shunts_fixed, i)
    bus_shunts_switched = _PM.ref(pm, nw, :bus_shunts_switched, i)

    bus_pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    bus_qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    bus_gs_fixed = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts_fixed)
    bus_bs_fixed = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts_fixed)
    bus_bs_switched = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts_switched)

    constraint_power_balance_ac_switched_shunt(pm, nw, i, bus, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts_fixed, bus_shunts_switched, bus_pd, bus_qd, bus_gs_fixed, bus_bs_fixed, bus_bs_switched)
end

function constraint_power_balance_ac_switched_shunt(pm::_PM.AbstractACPModel, n::Int, i::Int, bus, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts_fixed, bus_shunts_switched, pd, qd, gs_fixed, bs_fixed, bs_switched)
    vm = _PM.var(pm, n, :vm, i)
    p = _PM.var(pm, n, :p)
    q = _PM.var(pm, n, :q)
    pg = _PM.var(pm, n, :pg)
    qg = _PM.var(pm, n, :qg)
    pconv_grid_ac = _PM.var(pm, n, :pconv_tf_fr)
    qconv_grid_ac = _PM.var(pm, n, :qconv_tf_fr)

    shunt_bigM = get(_PM.var(pm, n), :shunt_bigM, Dict())

    JuMP.@NLconstraint(
        pm.model,
        (
            sum(p[a] for a in bus_arcs) +
            sum(pconv_grid_ac[c] for c in bus_convs_ac)
        ) == (
            sum(pg[g] for g in bus_gens) -
            sum(pd[d] for d in bus_loads) -
            sum(gs_fixed[s] for s in bus_shunts_fixed) * vm^2
        )
    )
    JuMP.@NLconstraint(
        pm.model,
        (
            sum(q[a] for a in bus_arcs) +
            sum(qconv_grid_ac[c] for c in bus_convs_ac)
        ) == (
            sum(qg[g] for g in bus_gens) -
            sum(qd[d] for d in bus_loads) +
            sum(bs_fixed[s] for s in bus_shunts_fixed) * vm^2 +
            sum(bs_switched[s] * shunt_bigM[s] for s in bus_shunts_switched) * vm^2
        )
    )
end

function constraint_power_balance_ac_soft_q_switched_shunt(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)

    bus_shunts_fixed = _PM.ref(pm, nw, :bus_shunts_fixed, i)
    bus_shunts_switched = _PM.ref(pm, nw, :bus_shunts_switched, i)

    bus_pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    bus_qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    bus_gs_fixed = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts_fixed)
    bus_bs_fixed = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts_fixed)
    bus_bs_switched = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts_switched)

    constraint_power_balance_ac_soft_q_switched_shunt(pm, nw, i, bus, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts_fixed, bus_shunts_switched, bus_pd, bus_qd, bus_gs_fixed, bus_bs_fixed, bus_bs_switched)
end

function constraint_power_balance_ac_soft_q_switched_shunt(pm::_PM.AbstractACPModel, n::Int, i::Int, bus, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts_fixed, bus_shunts_switched, pd, qd, gs_fixed, bs_fixed, bs_switched)
    vm = _PM.var(pm, n, :vm, i)
    p = _PM.var(pm, n, :p)
    q = _PM.var(pm, n, :q)
    pg = _PM.var(pm, n, :pg)
    qg = _PM.var(pm, n, :qg)
    pconv_grid_ac = _PM.var(pm, n, :pconv_tf_fr)
    qconv_grid_ac = _PM.var(pm, n, :qconv_tf_fr)

    qb_ac_pos_vio = _PM.var(pm, n, :qb_ac_pos_vio, i)
    qb_ac_neg_vio = _PM.var(pm, n, :qb_ac_neg_vio, i)

    shunt_bigM = get(_PM.var(pm, n), :shunt_bigM, Dict())

    JuMP.@NLconstraint(
        pm.model,
        (
            sum(p[a] for a in bus_arcs) +
            sum(pconv_grid_ac[c] for c in bus_convs_ac)
        ) == (
            sum(pg[g] for g in bus_gens) -
            sum(pd[d] for d in bus_loads) -
            sum(gs_fixed[s] for s in bus_shunts_fixed) * vm^2
        )
    )
    JuMP.@NLconstraint(
        pm.model,
        (
            qb_ac_pos_vio - qb_ac_neg_vio +
            sum(q[a] for a in bus_arcs) +
            sum(qconv_grid_ac[c] for c in bus_convs_ac)
        ) == (
            sum(qg[g] for g in bus_gens) -
            sum(qd[d] for d in bus_loads) +
            sum(bs_fixed[s] for s in bus_shunts_fixed) * vm^2 +
            sum(bs_switched[s] * shunt_bigM[s] for s in bus_shunts_switched) * vm^2
        )
    )
end

##########################################################################
# Soft tap limits constraint/variable
##########################################################################

function variable_transformer_tap_limit_violation_positive(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    soft_branch_indexes = [i for i in _PM.ids(pm, nw, :branch) if _PM.ref(pm, nw, :branch, i)["soft_tm"] == true]

    tm_pos_vio = _PM.var(pm, nw)[:tm_pos_vio] = JuMP.@variable(
        pm.model,
        [i in soft_branch_indexes],
        base_name = "$(nw)_tm_pos_vio",
        lower_bound = 0.0,
        upper_bound = 0.1,
    )

    if bounded
        for i in soft_branch_indexes
            JuMP.set_lower_bound(tm_pos_vio[i], 0.0)
            JuMP.set_upper_bound(tm_pos_vio[i], 0.1)
        end
    end

    report && _IM.sol_component_value(pm, _PM.pm_it_sym, nw, :branch, :tm_pos_vio, soft_branch_indexes, tm_pos_vio)
end

function variable_transformer_tap_limit_violation_negative(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    soft_branch_indexes = [i for i in _PM.ids(pm, nw, :branch) if _PM.ref(pm, nw, :branch, i)["soft_tm"] == true]
    tm_neg_vio = _PM.var(pm, nw)[:tm_neg_vio] = JuMP.@variable(pm.model, [i in soft_branch_indexes], base_name = "$(nw)_tm_neg_vio",)

    if bounded
        for i in soft_branch_indexes
            JuMP.set_lower_bound(tm_neg_vio[i], 0.0)
            JuMP.set_upper_bound(tm_neg_vio[i], 0.1)
        end
    end

    report && _IM.sol_component_value(pm, _PM.pm_it_sym, nw, :branch, :tm_neg_vio, soft_branch_indexes, tm_neg_vio)
end

function constraint_ohms_y_oltc_pst_from_soft(pm::AbstractACPModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr)
    p_fr = _PM.var(pm, n, :p, f_idx)
    q_fr = _PM.var(pm, n, :q, f_idx)
    vm_fr = _PM.var(pm, n, :vm, f_bus)
    vm_to = _PM.var(pm, n, :vm, t_bus)
    va_fr = _PM.var(pm, n, :va, f_bus)
    va_to = _PM.var(pm, n, :va, t_bus)
    tm = _PM.var(pm, n, :tm, f_idx[1])
    ta = _PM.var(pm, n, :ta, f_idx[1])

    tm_pos_vio = _PM.var(pm, n, :tm_pos_vio, f_idx[1])
    tm_neg_vio = _PM.var(pm, n, :tm_neg_vio, f_idx[1])

    tm_slack = tm + tm_pos_vio - tm_neg_vio

    JuMP.@NLconstraint(pm.model, p_fr == (g + g_fr) / tm_slack^2 * vm_fr^2 + (-g) / tm_slack * (vm_fr * vm_to * cos(va_fr - va_to - ta)) + (-b) / tm_slack * (vm_fr * vm_to * sin(va_fr - va_to - ta)))
    JuMP.@NLconstraint(pm.model, q_fr == -(b + b_fr) / tm_slack^2 * vm_fr^2 - (-b) / tm_slack * (vm_fr * vm_to * cos(va_fr - va_to - ta)) + (-g) / tm_slack * (vm_fr * vm_to * sin(va_fr - va_to - ta)))
end

function constraint_ohms_y_oltc_pst_from_soft(pm::AbstractPowerModel, i::Int; nw::Int=nw_id_default)
    branch = _PM.ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = calc_branch_y(branch)
    g_fr = branch["g_fr"]
    b_fr = branch["b_fr"]

    constraint_ohms_y_oltc_pst_from_soft(pm, nw, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr)
end

function constraint_ohms_y_oltc_pst_to_soft(pm::AbstractACPModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to)
    p_to = _PM.var(pm, n, :p, t_idx)
    q_to = _PM.var(pm, n, :q, t_idx)
    vm_fr = _PM.var(pm, n, :vm, f_bus)
    vm_to = _PM.var(pm, n, :vm, t_bus)
    va_fr = _PM.var(pm, n, :va, f_bus)
    va_to = _PM.var(pm, n, :va, t_bus)
    tm = _PM.var(pm, n, :tm, f_idx[1])
    ta = _PM.var(pm, n, :ta, f_idx[1])

    tm_pos_vio = _PM.var(pm, n, :tm_pos_vio, f_idx[1])
    tm_neg_vio = _PM.var(pm, n, :tm_neg_vio, f_idx[1])

    tm_slack = tm + tm_pos_vio - tm_neg_vio

    JuMP.@NLconstraint(pm.model, p_to == (g + g_to) * vm_to^2 + -g / tm_slack * (vm_to * vm_fr * cos(va_to - va_fr + ta)) + -b / tm_slack * (vm_to * vm_fr * sin(va_to - va_fr + ta)))
    JuMP.@NLconstraint(pm.model, q_to == -(b + b_to) * vm_to^2 - -b / tm_slack * (vm_to * vm_fr * cos(va_to - va_fr + ta)) + -g / tm_slack * (vm_to * vm_fr * sin(va_to - va_fr + ta)))
end

function constraint_ohms_y_oltc_pst_to_soft(pm::AbstractPowerModel, i::Int; nw::Int=nw_id_default)
    branch = _PM.ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = calc_branch_y(branch)
    g_to = branch["g_to"]
    b_to = branch["b_to"]

    constraint_ohms_y_oltc_pst_to_soft(pm, nw, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to)
end

##########################################################################
# Switched shunt variable definitions
##########################################################################

function ref_switched_shunt!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    _PM.apply_pm!(_ref_switched_shunt!, ref, data)
end

function _ref_switched_shunt!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    ref[:shunt_fixed] = Dict(x for x in ref[:shunt] if (!haskey(x.second, "switched") || !x.second["switched"]))
    ref[:shunt_switched] = Dict(x for x in ref[:shunt] if (haskey(x.second, "switched") && x.second["switched"]))

    bus_shunts_fixed = Dict((i, []) for (i, bus) in ref[:bus])
    for (i, shunt) in ref[:shunt_fixed]
        push!(bus_shunts_fixed[shunt["shunt_bus"]], i)
    end
    ref[:bus_shunts_fixed] = bus_shunts_fixed

    bus_shunts_switched = Dict((i, []) for (i, bus) in ref[:bus])
    for (i, shunt) in ref[:shunt_switched]
        push!(bus_shunts_switched[shunt["shunt_bus"]], i)
    end
    ref[:bus_shunts_switched] = bus_shunts_switched
end

function variable_switched_shunt_bigM(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    variable_shunt_indexes = [i for i in _PM.ids(pm, nw, :shunt_switched)]

    shunt_bigM = _PM.var(pm, nw)[:shunt_bigM] = JuMP.@variable(
        pm.model,
        [i in variable_shunt_indexes],
        base_name = "$(nw)_shunt_bigM",
        lower_bound = 0,
        upper_bound = 1,
    )

    report && _IM.sol_component_value(pm, _PM.pm_it_sym, nw, :shunt, :shunt_bigM, variable_shunt_indexes, shunt_bigM)
end

##########################################################################
# Generator on/off variable and constraints using big-M method
##########################################################################

function variable_generator_state(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    alpha_g = _PM.var(pm, nw)[:alpha_g] = JuMP.@variable(
        pm.model,
        [i in _PM.ids(pm, nw, :gen)],
        base_name = "$(nw)_alpha_g",
        lower_bound = 0,
        upper_bound = 1,
    )

    report && _PM.sol_component_value(pm, nw, :gen, :alpha_g, _PM.ids(pm, nw, :gen), alpha_g)
end

function constraint_generator_on_off(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    gen = _PM.ref(pm, nw, :gen, i)
    pmax = gen["pmax"]
    pmin = gen["pmin"]
    qmax = gen["qmax"]
    qmin = gen["qmin"]

    constraint_generator_on_off(pm, nw, i, pmax, pmin, qmax, qmin)
end

function constraint_generator_on_off(pm::_PM.AbstractACPModel, n::Int, i, pmax, pmin, qmax, qmin)
    pg = _PM.var(pm, n, :pg, i)
    qg = _PM.var(pm, n, :qg, i)
    alpha_g = _PM.var(pm, n, :alpha_g, i)

    JuMP.@constraint(pm.model, pg <= pmax * alpha_g)
    JuMP.@constraint(pm.model, pg >= pmin * alpha_g)
    JuMP.@constraint(pm.model, qg <= qmax * alpha_g)
    JuMP.@constraint(pm.model, qg >= qmin * alpha_g)
end

##########################################################################
# Utility functions for setting variable bounds
##########################################################################

function set_variable_bounds!(pm::_PM.AbstractPowerModel, n::Int, variable_name::Symbol, lower_bound::Float64, upper_bound::Float64)
    for i in _PM.ids(pm, nw=0, :bus)
        set_variable_bounds!(pm, n, i, variable_name, lower_bound, upper_bound)
    end
end

function set_variable_bounds!(pm::_PM.AbstractPowerModel, n::Int, i::Int, variable_name::Symbol, lower_bound::Float64, upper_bound::Float64)
    variable = _PM.var(pm, n, variable_name, i)

    JuMP.set_lower_bound(variable, lower_bound)
    JuMP.set_upper_bound(variable, upper_bound)
end
