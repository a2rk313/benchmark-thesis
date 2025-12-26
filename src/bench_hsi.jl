using YAXArrays
using Zarr
using Statistics
using Dates

FILE = "data/aviris_stress.zarr"

# 1. OPEN (Lazy)
# open_dataset returns a YAXArray wrapper around Zarr
cube = Cube(open_dataset(FILE))

println("Dataset Size: ", sizeof(cube) / 1e9, " GB")

t_start = now()

# 2. COMPUTE
# mapslices is optimized in YAXArrays to stream chunks
# dims=1 corresponds to the Band dimension
res = mapslices(mean, cube, dims=1)

# Trigger computation (YAXArrays is lazy until evaluated/saved)
# We map to a normal array to force the stream
final_res = Array(res)

elapsed = (now() - t_start).value / 1000.0
println("HSI Streaming Mean: ", elapsed, "s")
