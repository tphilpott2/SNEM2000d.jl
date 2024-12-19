# for use with isolate_section.py
function write_branch_flow_csv(target_dir, net; recalculate_flows=true)
    if recalculate_flows
        branch_res = calc_branch_flow_ac(net)
        PowerModels.update_data!(net, branch_res)
    end

    Sb = net["baseMVA"]
    # Sb = 1
    branch_flow_df = DataFrame(
        :ind => [parse(Int64, k) for (k, v) in net["branch"]],
        :loc_name => ["branch_$k" for (k, v) in net["branch"]],
        :outserv => [abs(v["br_status"] - 1) for (k, v) in net["branch"]],
        :f_bus => [net["bus"]["$(v["f_bus"])"]["name"] for (k, v) in net["branch"]],
        :t_bus => [net["bus"]["$(v["t_bus"])"]["name"] for (k, v) in net["branch"]],
        :pf => [v["pf"] * Sb for (k, v) in net["branch"]],
        :pt => [v["pt"] * Sb for (k, v) in net["branch"]],
        :qf => [v["qf"] * Sb for (k, v) in net["branch"]],
        :qt => [v["qt"] * Sb for (k, v) in net["branch"]],
    )

    sort!(branch_flow_df, :ind)
    select!(branch_flow_df, Not(:ind))

    CSV.write(target_dir, branch_flow_df)
end