# module SNEM2000d

using Pkg
# Activate the current project directory
function get_parent_dir(parent_dir::String, child_dir::String)
    println("searching for $parent_dir from $child_dir")
    dir_path = child_dir
    last_dir = dir_path
    while !endswith(dir_path, parent_dir)
        dir_path = dirname(dir_path)
        last_dir == dir_path && throw(ArgumentError("Package $parent_dir not found. last dir: $dir_path"))
        last_dir = dir_path
    end
    return dir_path
end
snem2000d_dir = get_parent_dir("SNEM2000d", @__DIR__)
Pkg.activate(snem2000d_dir)


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
# using PowerModelsACDCsecurityconstrained

const _PM = PowerModels
const _PMACDC = PowerModelsACDC
const _PMSC = PowerModelsSecurityConstrained
# const _PMACDCSC = PowerModelsACDCsecurityconstrained
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
include("analysis/small_signal_analysis_functions.jl")
include("analysis/mainland_lcc_analysis_functions.jl")
# end
