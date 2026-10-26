#!/usr/bin/env python3
"""Fetch the NASA images listed in nasa_sources.json and convert them for the apps.

Runs in CI (.github/workflows/nasa-assets.yml), where NASA's servers are reachable.
High-dynamic-range EXR maps (NASA SVS Deep Star Maps) are tone-mapped to JPEG: linear
light, scaled so the Milky Way's glow sits in the mid-tones, a soft shoulder so bright
stars don't clip harshly, then sRGB gamma. SDO sun images are cropped to the solar disc
(so the disc exactly fills the square, which is what the renderers assume) and, for the
flattened intensitygram, made gray (only its sunspots are used).

URLs can contain {yyyy}, {mm}, {dd}: the day before today (UTC), stepping back up to ten
days if NASA's archive doesn't have it yet.

    pip install OpenEXR numpy pillow
    python3 shared/tools/fetch_nasa_assets.py            # fetch and convert everything
    python3 shared/tools/fetch_nasa_assets.py --input starmap.exr   # convert a local file
"""
import argparse
import datetime
import json
import urllib.error
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
    # 0.14 in linear light, a dark sky with the Milky Way glowing in it. Calibrated
    # against Apple's own EXR-to-JPEG conversion of the same map (Photos on iPhone).
    key = float(np.percentile(luminance, 99.0)) or 1.0
    x = rgb * (0.14 / key)
    # Extended Reinhard: smooth roll-off, white point well above the Milky Way.
    white = 6.0
    x = x * (1 + x / (white * white)) / (1 + x)
    srgb = np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(np.clip(x, 0, None), 1 / 2.4) - 0.055)
    return (np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def crop_disc(image):
    """Crop to the solar disc's bounding square (drops the black sky and the label).

    Rows and columns crossing a wide chord of the disc find its middle; the disc's
    edges are then read along the middle row and column, which the corner labels on SDO
    images never reach."""
    bright = np.asarray(image.convert("L"), dtype=np.float32) > 40
    rows = np.where(bright.mean(axis=1) > 0.3)[0]
    cols = np.where(bright.mean(axis=0) > 0.3)[0]
    cy, cx = int((rows[0] + rows[-1]) / 2), int((cols[0] + cols[-1]) / 2)
    across = np.where(bright[cy])[0]
    down = np.where(bright[:, cx])[0]
    cx, cy = (across[0] + across[-1] + 1) / 2, (down[0] + down[-1] + 1) / 2
    r = max(across[-1] + 1 - across[0], down[-1] + 1 - down[0]) / 2
    return image.crop((round(cx - r), round(cy - r), round(cx + r), round(cy + r)))


def convert(source_file, kind, outputs):
    if kind == "exr-to-jpeg":
        image = Image.fromarray(tone_map(read_exr(source_file)), "RGB")
    elif kind == "crop-disc":
        image = crop_disc(Image.open(source_file).convert("RGB"))
    elif kind == "crop-disc-gray":
        image = crop_disc(Image.open(source_file).convert("RGB")).convert("L").convert("RGB")
    else:
        image = Image.open(source_file).convert("RGB")
    for out in outputs:
        path = ROOT / out["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        width = out.get("width", image.width)
        resized = image if width == image.width else image.resize((width, width * image.height // image.width), Image.LANCZOS)
        resized.save(path, quality=out.get("quality", 90), optimize=True)
        print(f"wrote {path.relative_to(ROOT)} ({resized.width} x {resized.height}, {path.stat().st_size // 1024} KB)")


def download(url, target):
    request = urllib.request.Request(url, headers={"User-Agent": "SunClock asset fetch (github.com/kramerlewis/circadian)"})
    with urllib.request.urlopen(request, timeout=300) as response, open(target, "wb") as f:
        while chunk := response.read(1 << 20):
            f.write(chunk)


def resolve(template):
    """Candidate URLs for a dated template, newest first."""
    if "{" not in template:
        return [template]
    today = datetime.datetime.now(datetime.timezone.utc).date()
    days = [today - datetime.timedelta(days=n) for n in range(1, 11)]
    return [template.format(yyyy=f"{d.year:04}", mm=f"{d.month:02}", dd=f"{d.day:02}") for d in days]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="convert this local file instead of downloading (first source only)")
    parser.add_argument("--force", action="store_true", help="fetch every source, even ones marked 'once'")
    args = parser.parse_args()
    manifest = json.load(open(Path(__file__).with_name("nasa_sources.json")))
    for source in manifest["sources"]:
        if args.input:
            convert(Path(args.input), source["convert"], source["outputs"])
            return
        if source.get("refresh") == "once" and not args.force and all((ROOT / o["path"]).exists() for o in source["outputs"]):
            print(f"have {source['name']}")
            continue
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "source"
            for url in resolve(source["url"]):
                try:
                    print(f"downloading {url}")
                    download(url, target)
                    break
                except urllib.error.HTTPError as error:
                    print(f"  {error.code}; trying an earlier day" if error.code == 404 else f"  {error}")
                    if error.code != 404:
                        raise
            else:
                raise SystemExit(f"no image found for {source['name']}")
            print(f"  {target.stat().st_size // 1024} KB")
            convert(target, source["convert"], source["outputs"])


if __name__ == "__main__":
    sys.exit(main())
