#!/usr/bin/env python3
"""Make the Earth texture for the 3D view: an equirectangular map (2:1, longitude -180
to 180 left to right, latitude 90 to -90 top to bottom) drawn from Natural Earth's land
polygons (public domain), as redistributed in the world-atlas npm package (ISC).

    npm pack world-atlas@2.0.2 && tar -xzf world-atlas-2.0.2.tgz
    python3 shared/tools/make_earth_texture.py package/land-50m.json shared/assets/earth.png

Colors are stylized, not imagery: deep and shallow ocean, land shaded by latitude from
tropical green through desert and temperate to tundra, and ice on Greenland, Antarctica
and land above about 66 degrees.
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 2048, 1024


def decode(topology, name="land"):
    """TopoJSON geometry -> list of polygons, each a list of rings of (lon, lat)."""
    sx, sy = topology["transform"]["scale"]
    tx, ty = topology["transform"]["translate"]
    arcs = []
    for arc in topology["arcs"]:
        x = y = 0
        points = []
        for dx, dy in arc:
            x += dx
            y += dy
            points.append((x * sx + tx, y * sy + ty))
        arcs.append(points)

    def ring(indices):
        points = []
        for i in indices:
            arc = arcs[i] if i >= 0 else list(reversed(arcs[~i]))
            points.extend(arc if not points else arc[1:])
        return points

    polygons = []
    for geometry in topology["objects"][name]["geometries"]:
        if geometry["type"] == "Polygon":
            polygons.append([ring(r) for r in geometry["arcs"]])
        elif geometry["type"] == "MultiPolygon":
            for polygon in geometry["arcs"]:
                polygons.append([ring(r) for r in polygon])
    return polygons


def to_pixel(lon, lat):
    return ((lon + 180) / 360 * WIDTH, (90 - lat) / 180 * HEIGHT)


def unwrap(ring):
    """Make longitudes continuous across the antimeridian. A ring that goes all the way
    round (Antarctica) is closed through the pole."""
    out = [ring[0]]
    for lon, lat in ring[1:]:
        prev = out[-1][0]
        while lon - prev > 180:
            lon -= 360
        while lon - prev < -180:
            lon += 360
        out.append((lon, lat))
    span = out[-1][0] - out[0][0]
    if abs(span) > 180:
        pole = -90 if sum(lat for _, lat in out) < 0 else 90
        out += [(out[-1][0], pole), (out[0][0], pole)]
    return out


def fill(draw, ring, value):
    ring = unwrap(ring)
    for shift in (-360, 0, 360):
        draw.polygon([to_pixel(lon + shift, lat) for lon, lat in ring], fill=value)


# (|latitude|, color): tropical green, subtropical desert, temperate, boreal, tundra.
LAND = [(0, (50, 108, 48)), (14, (66, 116, 50)), (22, (124, 128, 76)), (30, (132, 130, 82)),
        (38, (98, 124, 66)), (50, (78, 112, 60)), (60, (82, 104, 70)), (66, (138, 140, 120))]


def land_color(a):
    for (a0, c0), (a1, c1) in zip(LAND, LAND[1:]):
        if a <= a1:
            t = (a - a0) / (a1 - a0)
            return tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return LAND[-1][1]


def main(source, out):
    topology = json.load(open(source))
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(mask)
    for polygon in decode(topology):
        fill(draw, polygon[0], 255)
        for hole in polygon[1:]:
            fill(draw, hole, 0)
    coast = mask.filter(ImageFilter.GaussianBlur(10))

    image = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = image.load()
    land = mask.load()
    near = coast.load()
    for y in range(HEIGHT):
        lat = 90 - (y + 0.5) / HEIGHT * 180
        a = abs(lat)
        for x in range(WIDTH):
            lon = (x + 0.5) / WIDTH * 360 - 180
            if land[x, y] > 127:
                greenland = 60 < lat and -75 < lon < -10
                if a > 66 or greenland or lat < -60:
                    color = (234, 238, 242)  # ice
                else:
                    color = land_color(a)
            else:
                # Shallower, lighter water near the coasts.
                shallow = near[x, y] / 255
                color = (int(18 + 30 * shallow), int(52 + 50 * shallow), int(104 + 50 * shallow))
            pixels[x, y] = color
    image.resize((WIDTH // 2, HEIGHT // 2), Image.LANCZOS).save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
