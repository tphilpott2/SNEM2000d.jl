# module SNEM2000d

# using Pkg
# Pkg.activate(raw"C:\Users\tomph\.julia\dev\SNEM2000d")  # Activate the current project directory


using CSV
using DataFrames
using PowerModels # v0.19.10
using PowerModelsACDC
using PowerModelsSecurityConstrained
using StatsBase, JuMP, Ipopt
using InfrastructureModels
using Distributed
using OrderedCollections
using Plots
using PlotlyJS

# unregistered packages
using ISPhvdc
using PowerModelsACDCsecurityconstrained

const _PM = PowerModels
const _PMACDC = PowerModelsACDC
const _PMSC = PowerModelsSecurityConstrained
const _PMACDCSC = PowerModelsACDCsecurityconstrained
const _ISP = ISPhvdc
const _IM = InfrastructureModels
const _PL = Plots
const _PLJS = PlotlyJS


# OPF related functions
include("opf/prepare_opf_data.jl")
include("opf/constraint_and_variable.jl")
include("opf/run_opfs.jl")
include("opf/opf_analysis.jl")
include("opf/forms/uc_oltc_switched_shunt.jl")
include("opf/forms/uc_soft_q_soft_tap_switched_shunt.jl")

# make powerfactory model
include("make_powerfactory_model/prepare_NDD_for_export.jl")
include("make_powerfactory_model/write_pf_data_csvs/utils.jl")
include("make_powerfactory_model/write_pf_data_csvs/parse_hypersim_csvs.jl")
include("make_powerfactory_model/write_pf_data_csvs/write_network_data.jl")
include("make_powerfactory_model/write_pf_data_csvs/graphical_data.jl")
include("make_powerfactory_model/write_pf_data_csvs/write_branch_flows.jl")

# load flow verification
include("load_flow_verification/compare_load_flow.jl")

include("utils.jl")

# end
