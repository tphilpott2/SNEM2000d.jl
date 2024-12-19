function pu_Z_conversion(Z, S_old, S_new; V_old=1.0, V_new=1.0)
    return Z * (S_new / S_old) * (V_old / V_new)^2
end


# matches bus indexes to names
# get_bus_match(data) = Dict([
#     parse(Int64, k) => "name" ∉ keys(v) ? "bus_$(k)" : v["name"] for (k, v) in data["bus"]
# ])
function get_bus_match(data)
    bus_match = Dict()
    for (b, bus) in data["bus"]
        bus_match[bus["index"]] = bus["name"]
        bus_match[bus["name"]] = bus["index"]
    end
    return bus_match
end
function get_gen_match(data)
    # ind => name
    gen_match = Dict([
        k => "name" ∉ keys(v) ? "gen_$(k)" : v["name"] for (k, v) in data["gen"]
    ])
    # name => ind
    for (k, v) in data["gen"]
        gen_match[v["name"]] = k
    end
    return gen_match
end

# add shunt to powermodels
# doesnt add anything to net["shunt_data"]
function add_shunt!(data; shunt_entries::Dict=Dict(), shunt_data_entries::Dict=Dict())
    # add shunt
    shunt_index = maximum([parse(Int64, k) for k in keys(data["shunt"])]) + 1
    data["shunt"]["$(shunt_index)"] = Dict{String,Any}("index" => shunt_index)
    # add entries to shunt dict
    for (k, v) in shunt_entries
        data["shunt"]["$(shunt_index)"][k] = v
    end
    # add entries to shunt_data dict
    if shunt_data_entries != Dict()
        data["shunt_data"]["$(shunt_index)"] = Dict{String,Any}("index" => shunt_index)
        for (k, v) in shunt_data_entries
            data["shunt_data"]["$(shunt_index)"][k] = v
        end
    end
end

# prints the time taken to evaluate an expression
macro timed_print(message, expr)
    quote
        t0 = time()
        result = $(esc(expr))
        println($(message) * ": " * string(round(time() - t0, digits=3)) * " seconds")
        result
    end
end
