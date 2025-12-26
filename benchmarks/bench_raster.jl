using ArchGDAL, ImageFiltering

println("🔵 [JULIA] Raster: Focal Convolution (Slope)")

ArchGDAL.read("data/landsat_sample_cog.tif") do ds
    band = ArchGDAL.getband(ds, 1)
    w, h = ArchGDAL.width(ds), ArchGDAL.height(ds)
    # Read Float32
    data = Float32.(ArchGDAL.read(band, rows=div(h,4):div(h*3,4), cols=div(w,4):div(w*3,4)))

    # 2. FOCAL OPERATION (Gradient)
    # Using ImageFiltering.jl Kernel
    kern_x = Kernel.sobel()[1]
    kern_y = Kernel.sobel()[2]

    grad_x = imfilter(data, kern_x)
    grad_y = imfilter(data, kern_y)
    slope = hypot.(grad_x, grad_y)

    # 3. SAVE
    ArchGDAL.create("results/jl_slope.tif", driver=ArchGDAL.getdriver("GTiff"), width=size(data,2), height=size(data,1), nbands=1, dtype=Float32) do dest
        ArchGDAL.write!(dest, slope, 1)
    end
end
println("✅ Complete")
