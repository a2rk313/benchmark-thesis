# =============================================================================
# Unified Hashing Utilities for Julia
# =============================================================================

using SHA
using JSON3

const HASH_SAMPLES = 100

function sample_array(arr, n_samples=100)
    flat = vec(arr)
    len = length(flat)
    if len <= n_samples
        return collect(flat)
    end
    indices = round.(Int, range(1, len, length=n_samples))
    return [flat[i] for i in indices]
end

function round_val(v, precision=6)
    if v isa AbstractFloat
        return round(v; digits=precision)
    elseif v isa Integer
        return Int(v)
    else
        return v
    end
end

function generate_hash(data; n_samples=100)
    if data === nothing || isempty(data)
        return "0" ^ 16
    end

    local content::String

    if data isa AbstractVector && length(data) > 0
        if data[1] isa AbstractArray
            first_arr = nothing
            for item in data
                if item isa AbstractArray && length(item) > 0
                    first_arr = item
                    break
                end
            end
            if first_arr !== nothing
                sampled = sample_array(first_arr, n_samples)
                content = JSON3.write(round_val.(sampled))
            else
                content = "[]"
            end
        else
            sampled = sample_array(data, n_samples)
            content = JSON3.write(round_val.(sampled))
        end
    elseif data isa AbstractArray
        sampled = sample_array(data, n_samples)
        content = JSON3.write(round_val.(sampled))
    elseif data isa Dict || data isa NamedTuple
        items = Dict{String, Any}()
        ks = sort(collect(keys(data)))
        for k in ks
            v = data[k]
            if v isa AbstractArray
                sampled = sample_array(v, n_samples)
                items[string(k)] = round_val.(sampled)
            else
                items[string(k)] = round_val(v)
            end
        end
        content = JSON3.write(items)
    else
        content = JSON3.write(round_val(data))
    end

    h = bytes2hex(sha256(content))
    return h[1:16]
end
