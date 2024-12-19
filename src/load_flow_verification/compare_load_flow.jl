"""
Makes plots comparing the bus voltage and generator power results from powerfactory and powermodels.

PowerFactory results should be exported using the export_ldf_results.py script (stored in the same folder as this script).

Dataframes returned contain the powerfactory and powermodels results, as well as the error between the two results. Error is calculated as powerfactory_value / powermodels_value.
"""

using DataFrames, Plots, CSV

function plot_bus_voltage_comparison(ldf_results_dir, net::Dict{String,Any}; prefix="pf_ldf_results_")
    # get powerfactory results
    df_pf = CSV.File(joinpath(ldf_results_dir, "$(prefix)ElmTerm.csv")) |> DataFrame
    rename!(df_pf, :m_u => :u_pf, :m_phiu => :phi_pf)

    # get powermodels results
    df_pm = DataFrame(
        :loc_name => [bus["name"] for (b, bus) in net["bus"]],
        :u_pm => [bus["vm"] for (b, bus) in net["bus"]],
        :phi_pm => [bus["va"] for (b, bus) in net["bus"]],
    )

    # check for buses that dont exist in both results
    for row in eachrow(df_pf)
        if row.loc_name ∉ df_pm.loc_name
            println("Bus $(row.loc_name) not found in powermodels results")
        end
    end
    for row in eachrow(df_pm)
        if row.loc_name ∉ df_pf.loc_name
            println("Bus $(row.loc_name) not found in powerfactory results")
        end
    end

    # select only common buses
    df = innerjoin(df_pf, df_pm, on=:loc_name)

    # make plots
    pl_u = Plots.scatter(
        df.u_pf, df.u_pm,
        title="vm", label=false, size=(500, 500),
        xlabel="powerfactory", ylabel="powermodels"
    )
    pl_phi = Plots.scatter(
        df.phi_pf, df.phi_pm,
        title="va", label=false, size=(500, 500),
        xlabel="powerfactory", ylabel="powermodels"
    )
    pl = Plots.plot(
        pl_u, pl_phi,
        size=(1000, 500),
    )
    display(pl)

    # calculate error
    df.u_error = df.u_pf ./ df.u_pm
    df.phi_error = df.phi_pf ./ df.phi_pm

    return df
end

function plot_bus_voltage_comparison(
    ldf_results_dir,
    opf_results_dir::String,
    nem_2000_isphvdc::Dict{String,Any};
    prefix="pf_ldf_results_",
    return_plot=false,
    display_plot=true,
    radians=false,
    kwargs...
)
    # get powerfactory results
    df_pf = CSV.File(joinpath(ldf_results_dir, "$(prefix)ElmTerm.csv")) |> DataFrame
    rename!(df_pf, :m_u => :u_pf, :m_phiu => :phi_pf)

    # get powermodels results
    df_pm = CSV.File(joinpath(opf_results_dir, "bus.csv")) |> DataFrame
    bus_match = get_bus_match(nem_2000_isphvdc)
    df_pm.loc_name = [bus_match[row.ind] for row in eachrow(df_pm)]
    rename!(df_pm, :vm => :u_pm, :va => :phi_pm)
    select!(df_pm, :loc_name, :u_pm, :phi_pm)

    # check for buses that dont exist in both results
    for row in eachrow(df_pf)
        if row.loc_name ∉ df_pm.loc_name
            println("Bus $(row.loc_name) not found in powermodels results")
        end
    end
    for row in eachrow(df_pm)
        if row.loc_name ∉ df_pf.loc_name
            println("Bus $(row.loc_name) not found in powerfactory results")
        end
    end

    # select only common buses
    df = innerjoin(df_pf, df_pm, on=:loc_name)

    # convert phi to radians if requested
    if radians
        df.phi_pf = df.phi_pf .* π / 180
    else
        df.phi_pm = df.phi_pm .* 180 / π
    end

    # make plots
    pl_u = Plots.scatter(
        df.u_pf, df.u_pm,
        label=false, size=(500, 500),
        xlabel="PowerFactory Voltage Magnitude (p.u.)", ylabel="PowerModels Voltage Magnitude (p.u.)";
        kwargs...
    )
    pl_phi = Plots.scatter(
        df.phi_pf, df.phi_pm,
        label=false, size=(500, 500),
        xlabel="PowerFactory Voltage Angle (deg)", ylabel="PowerModels Voltage Angle (deg)";
        kwargs...
    )
    pl = Plots.plot(
        pl_u, pl_phi;
        kwargs...
    )

    # display plot if requested
    display_plot && display(pl)

    # return plot if requested
    if return_plot
        return pl
    else
        # calculate error
        df.u_error = df.u_pf ./ df.u_pm
        df.phi_error = df.phi_pf ./ df.phi_pm
        return df
    end
end

function plot_gen_power_comparison(ldf_results_dir, net::Dict{String,Any}; prefix="pf_ldf_results_")
    # get powerfactory results
    df_pf_ElmSym = CSV.File(joinpath(ldf_results_dir, "$(prefix)ElmSym.csv")) |> DataFrame
    df_pf_ElmGenstat = CSV.File(joinpath(ldf_results_dir, "$(prefix)ElmGenstat.csv")) |> DataFrame
    df_pf_ElmPvsys = CSV.File(joinpath(ldf_results_dir, "$(prefix)ElmPvsys.csv")) |> DataFrame

    # rename columns and select only relevant columns
    for df in [df_pf_ElmSym, df_pf_ElmGenstat, df_pf_ElmPvsys]
        rename!(df, :m_Psum_bus1 => :pg_pf, :m_Qsum_bus1 => :qg_pf)
        select!(df, [:loc_name, :pg_pf, :qg_pf])
    end

    # combine all powerfactory results
    df_pf = vcat(df_pf_ElmSym, df_pf_ElmGenstat, df_pf_ElmPvsys)

    # convert pf results from MW to p.u
    df_pf.pg_pf ./= net["baseMVA"]
    df_pf.qg_pf ./= net["baseMVA"]

    # get powermodels results
    df_pm = DataFrame(
        :loc_name => [gen["name"] for (g, gen) in net["gen"]],
        :pg_pm => [gen["pg"] for (g, gen) in net["gen"]],
        :qg_pm => [gen["qg"] for (g, gen) in net["gen"]],
    )

    # check for gens that dont exist in both results
    for row in eachrow(df_pf)
        if row.loc_name ∉ df_pm.loc_name
            println("Gen $(row.loc_name) not found in powermodels results")
        end
    end
    for row in eachrow(df_pm)
        if row.loc_name ∉ df_pf.loc_name
            println("Gen $(row.loc_name) not found in powerfactory results")
        end
    end

    # select only common gens
    df = innerjoin(df_pf, df_pm, on=:loc_name)

    # make plots
    pl_pg = Plots.scatter(
        df.pg_pf, df.pg_pm,
        title="pg", label=false, size=(500, 500),
        xlabel="powerfactory", ylabel="powermodels"
    )
    pl_qg = Plots.scatter(
        df.qg_pf, df.qg_pm,
        title="qg", label=false, size=(500, 500),
        xlabel="powerfactory", ylabel="powermodels"
    )
    pl = Plots.plot(
        pl_pg, pl_qg,
        size=(1000, 500),
    )
    display(pl)

    # calculate error
    df.pg_error = df.pg_pf ./ df.pg_pm
    df.qg_error = df.qg_pf ./ df.qg_pm

    return df
end
