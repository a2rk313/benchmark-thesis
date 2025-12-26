using ArchGDAL
using Dates

FILE = "data/landsat_cog.tif"

ArchGDAL.read(FILE) do ds
    width = ArchGDAL.width(ds)
    height = ArchGDAL.height(ds)

    # Calculate offsets
    off_x = div(width, 2)
    off_y = div(height, 2)

    t_start = now()

    # Read band 1, at offset x,y with size 512x512
    # This maps directly to GDAL RasterIO
    data = ArchGDAL.read(ds, 1, off_x, off_y, 512, 512)

    elapsed = (now() - t_start).value / 1000.0

    println("COG Window Read: ", elapsed, "s")
    println("Pixel Sum:       ", sum(data))
end
