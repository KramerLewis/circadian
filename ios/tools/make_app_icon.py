#!/usr/bin/env python3
"""Render SunClock's app icon (default, dark and tinted variants) into the asset catalog.

The icon is the app's dial: the sky ring colored by the sun's altitude through a summer
day (same color stops as SunCore's SkyGradient), with the glowing sun in the afternoon.

    python3 ios/tools/make_app_icon.py      # needs Pillow and NumPy
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "SunClock" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024
SCALE = 2  # supersampling for smooth edges

# Mirrors SkyGradient.lightStops / darkStops (ios/SunCore/Sources/SunCore/SkyGradient.swift),
# with the night end lifted slightly so the ring reads against the icon background.
LIGHT = [(-18, (0.16, 0.19, 0.40)), (-12, (0.20, 0.23, 0.46)), (-6, (0.33, 0.37, 0.66)),
         (-2.5, (0.74, 0.52, 0.66)), (-0.833, (0.96, 0.52, 0.36)), (4, (1.00, 0.64, 0.30)),
         (12, (1.00, 0.78, 0.40)), (30, (1.00, 0.87, 0.50)), (55, (1.00, 0.94, 0.66)),
         (75, (1.00, 0.98, 0.84))]
DARK = [(-18, (0.10, 0.12, 0.27)), (-12, (0.12, 0.14, 0.32)), (-6, (0.21, 0.25, 0.48)),
        (-2.5, (0.52, 0.36, 0.50)), (-0.833, (0.80, 0.40, 0.26)), (4, (0.88, 0.50, 0.22)),
        (12, (0.90, 0.63, 0.28)), (30, (0.92, 0.72, 0.36)), (55, (0.95, 0.80, 0.48)),
        (75, (0.97, 0.86, 0.62))]
BRIGHTNESS = [(-18, 0.22), (-12, 0.28), (-6, 0.38), (-0.833, 0.55), (10, 0.72), (35, 0.88), (70, 1.0)]

LATITUDE, DECLINATION = 47.6, 20.0  # a long summer day
SUN_ANGLE = 42.0                   # degrees clockwise from the top: mid-afternoon


def interpolate(stops, altitude):
    xs = np.array([s[0] for s in stops])
    values = np.array([s[1] for s in stops], dtype=float)
    if values.ndim == 1:
        return np.interp(altitude, xs, values)
    return np.stack([np.interp(altitude, xs, values[:, i]) for i in range(values.shape[1])], axis=-1)


def render(variant):
    n = SIZE * SCALE
    y, x = np.mgrid[0:n, 0:n].astype(float) + 0.5
    cx = cy = n / 2
    dx, dy = x - cx, y - cy
    r = np.hypot(dx, dy) / n                      # radius as a fraction of the icon size
    angle = np.degrees(np.arctan2(dx, -dy))       # clockwise from the top
    lat, dec = math.radians(LATITUDE), math.radians(DECLINATION)
    altitude = np.degrees(np.arcsin(
        math.sin(lat) * math.sin(dec) + math.cos(lat) * math.cos(dec) * np.cos(np.radians(angle))))

    # Background.
    t = y / n
    if variant == "default":
        top, bottom = np.array([0.09, 0.11, 0.25]), np.array([0.03, 0.04, 0.11])
    else:
        top, bottom = np.array([0.04, 0.04, 0.07]), np.array([0.0, 0.0, 0.0])
    image = top + (bottom - top) * t[..., None]

    # Sky ring.
    outer, inner = 0.40, 0.27
    ring = np.clip((outer - r) * n, 0, 1) * np.clip((r - inner) * n, 0, 1)
    if variant == "tinted":
        # Dimmer than the sun so it stands out once the system tints the icon.
        sky = np.repeat(interpolate(BRIGHTNESS, altitude)[..., None] * 0.72, 3, axis=-1)
    else:
        sky = interpolate(LIGHT if variant == "default" else DARK, altitude)
    image = image * (1 - ring[..., None]) + sky * ring[..., None]

    # Glowing sun on the ring.
    mid = (outer + inner) / 2
    sx = cx + mid * n * math.sin(math.radians(SUN_ANGLE))
    sy = cy - mid * n * math.cos(math.radians(SUN_ANGLE))
    d = np.hypot(x - sx, y - sy) / n
    glow_color = np.array([1.0, 1.0, 1.0]) if variant == "tinted" else np.array([1.0, 0.58, 0.12])
    glow = np.exp(-((d / 0.075) ** 2)) * 0.85
    image = image * (1 - glow[..., None]) + glow_color * glow[..., None]
    core_radius = 0.052
    core = np.clip((core_radius - d) * n, 0, 1)
    core_color = np.array([1.0, 1.0, 1.0]) if variant == "tinted" else np.array([1.0, 0.97, 0.86])
    image = image * (1 - core[..., None]) + core_color * core[..., None]

    pixels = (np.clip(image, 0, 1) * 255 + 0.5).astype(np.uint8)
    # RGB, no alpha: App Store icons must be opaque.
    return Image.fromarray(pixels, "RGB").resize((SIZE, SIZE), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for variant, name in [("default", "AppIcon.png"), ("dark", "AppIcon-Dark.png"), ("tinted", "AppIcon-Tinted.png")]:
        render(variant).save(OUT / name, optimize=True)
        print("wrote", OUT / name)


if __name__ == "__main__":
    main()
