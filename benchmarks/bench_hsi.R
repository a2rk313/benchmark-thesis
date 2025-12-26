library(stars); library(rmatio)

cat("🟣 [R] HSI: Correlation Matrix\n")

# 1. LOAD (Fallback to .mat for stability)
raw <- read.mat("data/PaviaU.mat")$paviaU
# Convert to matrix (Pixels x Bands)
dims <- dim(raw)
flat <- matrix(raw, nrow=dims[1]*dims[2], ncol=dims[3])

# 2. CORRELATION MATRIX (Base R optimized C)
corr_mat <- cor(flat)

# 3. SAVE
write.csv(corr_mat, "results/r_corr_matrix.csv")
cat("✅ Complete\n")
