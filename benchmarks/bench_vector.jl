using ArchGDAL, DataFrames

println("🟢 [JULIA] Vector: Reprojection & Buffer Stress")

# 1. LOAD
cities = ArchGDAL.read("data/ne_10m_populated_places.shp")
countries = ArchGDAL.read("data/ne_10m_admin_0_countries.shp")

# 2. FILTER & JOIN
cty_layer = ArchGDAL.getlayer(cities, 0)

# 3. REPROJECT SETUP (Source WGS84 -> Target WebMercator)
src_spatial_ref = ArchGDAL.importEPSG(4326)
dst_spatial_ref = ArchGDAL.importEPSG(3857)
coord_trans = ArchGDAL.createcoordtrans(src_spatial_ref, dst_spatial_ref)

buffered_geoms = []
areas = []

# Manual Loop to stress the C-API calls
for i in 0:ArchGDAL.nfeature(cty_layer)-1
    feat = ArchGDAL.getfeature(cty_layer, i)
    geom = ArchGDAL.getgeometry(feat)

    # Reproject Geometry (Heavy Math)
    ArchGDAL.transform!(geom, coord_trans)

    # Buffer (10km)
    buf_geom = ArchGDAL.buffer(geom, 10000)
    push!(buffered_geoms, buf_geom)

    # Calc Area
    push!(areas, ArchGDAL.geomarea(buf_geom) / 1e6)
end
println("✅ Complete")
