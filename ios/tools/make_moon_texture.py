#!/usr/bin/env python3
"""Make the moon disc texture the app draws, from NASA's LRO color map.

Source: ios/tools/lroc_color_2k.jpg, the "CGI Moon Kit" color map from NASA's
Scientific Visualization Studio (https://svs.gsfc.nasa.gov/4720), an equirectangular
map with the near side centered. This projects the near side orthographically (the
face we see from Earth, north up) into a square RGBA image with transparent corners.
It's albedo only; the app adds the phase lighting.

    python3 ios/tools/make_moon_texture.py      # needs Pillow and NumPy
"""

from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "lroc_color_2k.jpg"
OUT = HERE.parent / "Shared" / "MoonTexture.png"
SIZE = 256
SCALE = 4  # supersample, then downscale for clean edges


def main():
    src = np.asarray(Image.open(SOURCE).convert("RGB"), dtype=float) / 255
    h, w, _ = src.shape
    n = SIZE * SCALE
    y, x = np.mgrid[0:n, 0:n].astype(float) + 0.5
    x = (x - n / 2) / (n / 2)
    y = -(y - n / 2) / (n / 2)
    r2 = x * x + y * y
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    lat = np.arcsin(np.clip(y, -1, 1))
    lon = np.arctan2(x, z)
    u = ((lon / (2 * np.pi) + 0.5) * w).astype(int) % w
    v = np.clip(((0.5 - lat / np.pi) * h).astype(int), 0, h - 1)
    rgb = src[v, u]
    alpha = np.clip((1 - np.sqrt(r2)) * n / 2, 0, 1)
    rgba = np.dstack([rgb, alpha])
    image = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    image.save(OUT, optimize=True)
    print("wrote", OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
