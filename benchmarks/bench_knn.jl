using ArchGDAL, NearestNeighbors, StaticArrays, Statistics, CSV, DataFrames

println("🟠 [JULIA] KNN: Density Search (K=50)")

ds = ArchGDAL.read("data/ne_10m_populated_places.shp")
l = ArchGDAL.getlayer(ds, 0)
coords = [SVector(ArchGDAL.getx(g,0), ArchGDAL.gety(g,0)) for g in (ArchGDAL.getgeometry(f) for f in l)]

    # 1. INDEX
    tree = KDTree(coords)

    # 2. QUERY 50 NEIGHBORS
    idxs, dists = knn(tree, coords, 50, true)

    # 3. MEAN DISTANCE
    mean_dists = [mean(d) for d in dists]

        # CSV.write("results/jl_knn_density.csv", DataFrame(Mean=mean_dists))
        println("✅ Complete")
