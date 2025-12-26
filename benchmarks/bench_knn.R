library(sf); library(class)

cat("🟠 [R] KNN: Density Search (K=50)\n")

cities <- st_read("data/ne_10m_populated_places.shp", quiet=TRUE)
coords <- st_coordinates(cities)

# 2. QUERY 50 NEIGHBORS
# R 'knn' from class package only returns the *label* of the neighbors.
# We stress the "Search" phase here.
res <- knn(train=coords, test=coords, cl=factor(1:nrow(coords)), k=50)

cat("✅ Complete\n")
