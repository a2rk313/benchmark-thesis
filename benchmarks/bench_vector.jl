using ArchGDAL
using Dates

FILE = "data/ne_10m_populated_places.shp"

# 1. READ (I/O)
t_start = now()
ds = ArchGDAL.read(FILE)
layer = ArchGDAL.getlayer(ds, 0)
# Force reading features into memory to match Python/R behavior
features = [ArchGDAL.getfeature(layer, i) for i in 0:ArchGDAL.nfeature(layer)-1]
    geoms = [ArchGDAL.getgeometry(f) for f in features]
        read_time = (now() - t_start).value / 1000.0

        # 2. COMPUTE (CPU FPU)
        t_start = now()
        # Broadcast buffer function over the array of geometries
        buffered = ArchGDAL.buffer.(geoms, 0.1)
        compute_time = (now() - t_start).value / 1000.0

        println("Vector Read:    ", read_time, "s")
        println("Vector Buffer:  ", compute_time, "s")
        println("Total Geoms:    ", length(geoms))
