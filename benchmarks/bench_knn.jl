using ArchGDAL
using NearestNeighbors
using StaticArrays
using Dates

FILE = "data/ne_10m_populated_places.shp"

# Setup
ds = ArchGDAL.read(FILE)
layer = ArchGDAL.getlayer(ds, 0)
points = [ArchGDAL.getpoint(ArchGDAL.getfeature(layer, i), 0) for i in 0:ArchGDAL.nfeature(layer)-1]
    coords = [SVector(ArchGDAL.getx(p), ArchGDAL.gety(p)) for p in points]
        data = repeat(coords, 10)

        println("Benchmarking KNN on ", length(data), " points...")

        # 1. INDEX
        t_start = now()
        # KDTree from NearestNeighbors.jl is pure Julia, heavily optimized
        tree = KDTree(data)
        idx_time = (now() - t_start).value / 1000.0

        # 2. QUERY
        t_start = now()
        # knn for every point in the set
        idxs, dists = knn(tree, data, 5, true)
        query_time = (now() - t_start).value / 1000.0

        println("Index Build: ", idx_time, "s")
        println("Query Time:  ", query_time, "s")
