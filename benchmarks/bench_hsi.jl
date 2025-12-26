using YAXArrays, Zarr, Statistics, CSV, DataFrames

println("🟣 [JULIA] HSI: Correlation Matrix")

# 1. LOAD
cube = Cube("data/pavia.zarr")

# 2. RESHAPE (Lazy)
# YAXArrays doesn't support easy stack(), so we read to memory for the Algebra stress
full_data = read(cube) # Reads into RAM
s = size(full_data)
flat = reshape(full_data, s[1]*s[2], s[3])

# 3. CORRELATION (Linear Algebra)
corr_mat = cor(flat)

# 4. SAVE
CSV.write("results/jl_corr_matrix.csv", Tables.table(corr_mat))
println("✅ Complete")
