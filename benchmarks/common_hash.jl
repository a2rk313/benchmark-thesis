# =============================================================================
# Unified Hashing Utilities for Julia
# Uses consistent sampling for cross-language validation.
# =============================================================================

using SHA

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

# Convert data to JSON-compatible string for consistent cross-language hashing
function json_stringify_vector(vec)
    # Convert to JSON array format: [1.234567, 2.345678, ...]
    elements = ["$(round(v, digits=6))" for v in vec]
    return "[" * join(elements, ", ") * "]"
end

function generate_hash(data; n_samples=100)
    if data === nothing || isempty(data)
        return "0" ^ 16
    end

    # Import JSON for consistent formatting with Python
    json_str = ""

    try
        using JSON
        json_available = true
    catch
        json_available = false
    end

    local content::String

    if data isa AbstractVector && length(data) > 0
        if data[1] isa AbstractArray
            local first_arr
            for item in data
                if item isa AbstractArray && length(item) > 0
                    first_arr = item
                    break
                end
            end
            if first_arr !== nothing
                sampled = sample_array(first_arr, n_samples)
                if json_available
                    content = JSON.json(round_val.(sampled))
                else
                    content = json_stringify_vector(round_val.(sampled))
                end
            else
                content = "[]"
            end
        else
            sampled = sample_array(data, n_samples)
            if json_available
                content = JSON.json(round_val.(sampled))
            else
                content = json_stringify_vector(round_val.(sampled))
            end
        end
    elseif data isa AbstractArray
        sampled = sample_array(data, n_samples)
        if json_available
            content = JSON.json(round_val.(sampled))
        else
            content = json_stringify_vector(round_val.(sampled))
        end
    elseif data isa Dict || data isa NamedTuple
        items = Dict{String, Any}()
        if data isa NamedTuple
            keys = collect(keys(data)) |> sort
        else
            keys = sort(collect(keys(data)))
        end
        for k in keys
            v = data[k]
            if v isa AbstractArray
                sampled = sample_array(v, n_samples)
                items[string(k)] = round_val.(sampled)
            else
                items[string(k)] = round_val(v)
            end
        end
        if json_available
            content = JSON.json(items)
        else
            # Manual JSON formatting
            pairs = ["\"$k\": $(v isa AbstractArray ? json_stringify_vector(v) : v)" for (k, v) in items]
            content = "{" * join(pairs, ", ") * "}"
        end
    else
        if json_available
            content = JSON.json(round_val(data))
        else
            content = string(round_val(data))
        end
    end

    h = bytes2hex(sha256(content))
    return h[1:16]
end
