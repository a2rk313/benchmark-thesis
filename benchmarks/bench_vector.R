library(sf); library(dplyr)

cat("🟢 [R] Vector: Reprojection & Buffer Stress\n")

# 1. LOAD
cities <- st_read("data/ne_10m_populated_places.shp", quiet=TRUE)
countries <- st_read("data/ne_10m_admin_0_countries.shp", quiet=TRUE)

# 2. FILTER & JOIN
large_countries <- filter(countries, POP_EST > 10000000)
selected_cities <- st_join(cities, large_countries, join=st_within, left=FALSE)

# 3. REPROJECT (Heavy)
selected_cities <- st_transform(selected_cities, 3857)

# 4. BUFFER & AREA
buffered <- st_buffer(selected_cities, dist=10000)
buffered$area_km2 <- st_area(buffered) / 1e6

# 5. SAVE
dir.create("results", showWarnings=FALSE)
st_write(buffered, "results/r_site_selection.gpkg", delete_dsn=TRUE, quiet=TRUE)
cat("✅ Complete\n")
