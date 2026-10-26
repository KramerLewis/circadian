#!/usr/bin/env python3
"""Make the Earth textures for the 3D view from NASA imagery in shared/assets/nasa/:

- Blue Marble Next Generation (topography and bathymetry), NASA Earth Observatory:
  world.topo.bathy.200406.3x5400x2700.jpg (June 2004)
- Black Marble 2016 (Earth at night), NASA Earth Observatory: BlackMarble_2016_01deg.jpg

Both are equirectangular (longitude -180 to 180 left to right, latitude 90 to -90 top
to bottom), which is what the renderers sample. Writes 2048 x 1024 JPEGs:

    python3 shared/tools/make_earth_textures.py web/public
"""
import sys
from pathlib import Path

from PIL import Image

SOURCES = Path(__file__).resolve().parent.parent / "assets" / "nasa"
SIZE = (2048, 1024)


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    day = Image.open(SOURCES / "world.topo.bathy.200406.3x5400x2700.jpg").convert("RGB")
    day.resize(SIZE, Image.LANCZOS).save(out / "earth-day.jpg", quality=85, optimize=True)
    night = Image.open(SOURCES / "BlackMarble_2016_01deg.jpg").convert("RGB")
    night.resize(SIZE, Image.LANCZOS).save(out / "earth-night.jpg", quality=85, optimize=True)
    print(f"wrote {out / 'earth-day.jpg'} and {out / 'earth-night.jpg'}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "web/public")
