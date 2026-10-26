#!/usr/bin/env python3
"""Fetch the NASA images listed in nasa_sources.json and convert them for the apps.

Runs in CI (.github/workflows/nasa-assets.yml), where NASA's servers are reachable.
High-dynamic-range EXR maps (NASA SVS Deep Star Maps) are tone-mapped to JPEG: linear
light, scaled so the Milky Way's glow sits in the mid-tones, a soft shoulder so bright
stars don't clip harshly, then sRGB gamma.

    pip install OpenEXR numpy pillow
    python3 shared/tools/fetch_nasa_assets.py            # fetch and convert everything
    python3 shared/tools/fetch_nasa_assets.py --input starmap.exr   # convert a local file
"""
import argparse
import json
import sys
import tempfile
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def read_exr(path):
    import OpenEXR

    with OpenEXR.File(str(path)) as f:
        channels = f.channels()
        if "RGB" in channels:
            rgb = np.asarray(channels["RGB"].pixels, dtype=np.float32)
        else:
            rgb = np.stack([np.asarray(channels[c].pixels, dtype=np.float32) for c in "RGB"], axis=-1)
    return np.nan_to_num(np.clip(rgb, 0, None))


def tone_map(rgb):
    """Linear HDR -> 8-bit sRGB."""
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    # Exposure from the sky itself: the 99th percentile (the bright Milky Way) maps to
    # about 0.8 before the shoulder, so faint glow stays visible and stars still pop.
    key = float(np.percentile(luminance, 99.0)) or 1.0
    x = rgb * (0.8 / key)
    # Extended Reinhard: smooth roll-off, white point well above the Milky Way.
    white = 6.0
    x = x * (1 + x / (white * white)) / (1 + x)
    srgb = np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(np.clip(x, 0, None), 1 / 2.4) - 0.055)
    return (np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def convert(source_file, kind, outputs):
    if kind == "exr-to-jpeg":
        image = Image.fromarray(tone_map(read_exr(source_file)), "RGB")
    else:
        image = Image.open(source_file).convert("RGB")
    for out in outputs:
        path = ROOT / out["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        width = out.get("width", image.width)
        resized = image if width == image.width else image.resize((width, width * image.height // image.width), Image.LANCZOS)
        resized.save(path, quality=out.get("quality", 90), optimize=True)
        print(f"wrote {path.relative_to(ROOT)} ({resized.width} x {resized.height}, {path.stat().st_size // 1024} KB)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="convert this local file instead of downloading (first source only)")
    args = parser.parse_args()
    manifest = json.load(open(Path(__file__).with_name("nasa_sources.json")))
    for source in manifest["sources"]:
        if args.input:
            convert(Path(args.input), source["convert"], source["outputs"])
            return
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / Path(source["url"]).name
            print(f"downloading {source['url']}")
            request = urllib.request.Request(source["url"], headers={"User-Agent": "SunClock asset fetch (github.com/kramerlewis/circadian)"})
            with urllib.request.urlopen(request, timeout=300) as response, open(target, "wb") as f:
                while chunk := response.read(1 << 20):
                    f.write(chunk)
            print(f"  {target.stat().st_size // (1 << 20)} MB")
            convert(target, source["convert"], source["outputs"])


if __name__ == "__main__":
    sys.exit(main())
