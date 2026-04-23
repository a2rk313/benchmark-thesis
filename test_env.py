import os
from pathlib import Path
print(f"CWD: {os.getcwd()}")
path = "data/natural_earth_countries.gpkg"
print(f"Path '{path}' exists: {os.path.exists(path)}")
