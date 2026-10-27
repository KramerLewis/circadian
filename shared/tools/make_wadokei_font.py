#!/usr/bin/env python3
"""Subset the brush font for the wadokei kanji to just the characters the dial uses.

Yuji Syuku (SIL Open Font License 1.1), from the @fontsource/yuji-syuku npm package:

    npm pack @fontsource/yuji-syuku@5.3.1 && tar -xzf fontsource-yuji-syuku-5.3.1.tgz
    pip install fonttools brotli
    python3 shared/tools/make_wadokei_font.py package/files/yuji-syuku-japanese-400-normal.woff2 web/public/fonts ios/Shared/Wadokei

The web gets WOFF2; iOS and watchOS, which can't read WOFF2, get the same subset as TTF.

The subset is renamed (the OFL asks modified fonts not to use the original's name) and
ships with the license.
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

# The zodiac kanji and the bell counts the hours were called by.
CHARACTERS = "子丑寅卯辰巳午未申酉戌亥九八七六五四つ"
FAMILY = "SunClock Wadokei"


def main(source, out_dir, ttf_dir=None):
    font = TTFont(source)
    options = subset.Options()
    options.flavor = "woff2"
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=CHARACTERS)
    subsetter.subset(font)
    for record in font["name"].names:
        if record.nameID in (1, 4, 16, 21):
            record.string = FAMILY
        elif record.nameID == 6:
            record.string = FAMILY.replace(" ", "")
        elif record.nameID == 3:
            record.string = f"{FAMILY}; subset of Yuji Syuku"
    out = Path(out_dir) / "wadokei.woff2"
    font.flavor = "woff2"
    font.save(out)
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    if ttf_dir:
        ttf = Path(ttf_dir) / "SunClockWadokei.ttf"
        font.flavor = None
        font.save(ttf)
        print(f"wrote {ttf} ({ttf.stat().st_size} bytes)")


if __name__ == "__main__":
    main(*sys.argv[1:4])
