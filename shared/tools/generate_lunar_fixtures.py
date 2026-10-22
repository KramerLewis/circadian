#!/usr/bin/env python3
"""Generate shared/fixtures/lunar-reference.json.

Reference implementation of the moon calculations every platform ports: the moon's
position from Meeus, Astronomical Algorithms ch. 47 (meeus_moon.py, about 10"),
rise/set at the standard altitude 0.7275 * parallax - 34', meridian transits, and the
illuminated fraction from the sun-moon elongation (sun from the NOAA formulas in
generate_solar_fixtures.py).

Events are found the way the apps find them: sample every 10 minutes, then bisect.

Usage:
    python3 shared/tools/generate_lunar_fixtures.py            # write the fixture
    python3 shared/tools/generate_lunar_fixtures.py --check    # fail if it is stale
    python3 shared/tools/generate_lunar_fixtures.py --ephem    # cross-check with PyEphem
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meeus_moon  # noqa: E402
from generate_solar_fixtures import julian_century  # noqa: E402

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "lunar-reference.json"
TOLERANCE_SECONDS = 120
ILLUMINATION_TOLERANCE = 0.01
STEP_SECONDS = 600

CASES = [
    ("Seattle, June solstice", 47.61, -122.33, "America/Los_Angeles", "2026-06-21"),
    ("Seattle, full moon", 47.61, -122.33, "America/Los_Angeles", "2026-11-24"),
    ("Seattle, new moon", 47.61, -122.33, "America/Los_Angeles", "2026-12-09"),
    ("Seattle, DST ends", 47.61, -122.33, "America/Los_Angeles", "2026-11-01"),
    ("Seattle, December solstice", 47.61, -122.33, "America/Los_Angeles", "2026-12-21"),
    ("Sydney", -33.87, 151.21, "Australia/Sydney", "2026-06-21"),
    ("Tromso, January", 69.65, 18.96, "Europe/Oslo", "2026-01-12"),
    ("Equator, prime meridian", 0.0, 0.0, "UTC", "2026-10-22"),
]

R, D = math.radians, math.degrees


def rev(x: float) -> float:
    return x % 360.0


def moon_position(t: float) -> dict:
    """Geocentric moon at Unix time t: ecliptic lon/lat, RA/Dec (deg), distance (Earth radii)."""
    return meeus_moon.position(t)


def sun_longitude(t: float) -> float:
    """Apparent ecliptic longitude of the sun (NOAA formulas)."""
    T = julian_century(t)
    l0 = (280.46646 + T * (36000.76983 + 0.0003032 * T)) % 360
    mr = R(357.52911 + T * (35999.05029 - 0.0001537 * T))
    center = (math.sin(mr) * (1.914602 - T * (0.004817 + 0.000014 * T))
              + math.sin(2 * mr) * (0.019993 - 0.000101 * T) + math.sin(3 * mr) * 0.000289)
    omega = 125.04 - 1934.136 * T
    return (l0 + center - 0.00569 - 0.00478 * math.sin(R(omega))) % 360


def hour_angle(t: float, longitude: float, ra: float) -> float:
    """Local hour angle in (-180, 180]."""
    jd = t / 86400 + 2440587.5
    T = (jd - 2451545) / 36525
    gmst = 280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * T * T
    h = rev(gmst + longitude - ra)
    return h - 360 if h > 180 else h


def altitude(t: float, lat: float, lon: float) -> float:
    p = moon_position(t)
    h = hour_angle(t, lon, p["ra"])
    return D(math.asin(math.sin(R(lat)) * math.sin(R(p["dec"])) + math.cos(R(lat)) * math.cos(R(p["dec"])) * math.cos(R(h))))


def rise_set_function(t: float, lat: float, lon: float) -> float:
    """Altitude above the rise/set altitude; positive while the moon is up."""
    parallax = D(math.asin(1 / moon_position(t)["distance"]))
    return altitude(t, lat, lon) - (0.7275 * parallax - 34 / 60)


def illumination(t: float) -> tuple[float, bool]:
    p = moon_position(t)
    ls = sun_longitude(t)
    elongation = D(math.acos(math.cos(R(p["lat"])) * math.cos(R(p["lon"] - ls))))
    return (1 - math.cos(R(elongation))) / 2, rev(p["lon"] - ls) < 180


def bisect(f, a: float, b: float) -> float:
    fa = f(a)
    for _ in range(30):
        mid = (a + b) / 2
        fm = f(mid)
        if (fm > 0) == (fa > 0):
            a, fa = mid, fm
        else:
            b = mid
    return (a + b) / 2


def events(t0: float, t1: float, lat: float, lon: float) -> list[tuple[str, float]]:
    """Moonrise, moonset, transit and lower transit in [t0, t1), chronological."""
    def upper(x):
        return hour_angle(x, lon, moon_position(x)["ra"])

    def lower(x):
        h = upper(x) - 180
        return h + 360 if h <= -180 else h

    out = []
    t = t0
    prev = (rise_set_function(t, lat, lon), upper(t), lower(t))
    while t < t1:
        nxt = min(t + STEP_SECONDS, t1)
        cur = (rise_set_function(nxt, lat, lon), upper(nxt), lower(nxt))
        if prev[0] < 0 <= cur[0]:
            out.append(("moonrise", bisect(lambda x: rise_set_function(x, lat, lon), t, nxt)))
        if prev[0] >= 0 > cur[0]:
            out.append(("moonset", bisect(lambda x: rise_set_function(x, lat, lon), t, nxt)))
        # A hour-angle crossing of 0 (not the wrap at 180) is a transit.
        if prev[1] < 0 <= cur[1] and cur[1] - prev[1] < 90:
            out.append(("moonTransit", bisect(upper, t, nxt)))
        if prev[2] < 0 <= cur[2] and cur[2] - prev[2] < 90:
            out.append(("moonLowerTransit", bisect(lower, t, nxt)))
        t, prev = nxt, cur
    return sorted(out, key=lambda e: e[1])


def build_fixture() -> dict:
    cases = []
    for name, lat, lon, tz_name, day in CASES:
        tz = ZoneInfo(tz_name)
        start = datetime.combine(date.fromisoformat(day), time(0, 0), tzinfo=tz)
        end = datetime.combine(date.fromisoformat(day) + timedelta(days=1), time(0, 0), tzinfo=tz)
        noon = datetime.combine(date.fromisoformat(day), time(12, 0), tzinfo=tz).timestamp()
        fraction, waxing = illumination(noon)
        cases.append({
            "name": name, "latitude": lat, "longitude": lon, "timeZone": tz_name, "date": day,
            "events": [{"event": e, "time": datetime.fromtimestamp(round(t), tz).isoformat()}
                       for e, t in events(start.timestamp(), end.timestamp(), lat, lon)],
            "illuminationAtNoon": round(fraction, 4),
            "waxingAtNoon": waxing,
        })
    return {
        "description": "Reference moon events (within each local calendar day) and illumination for every platform's lunar calculator tests.",
        "generatedBy": "shared/tools/generate_lunar_fixtures.py",
        "algorithm": "Meeus ch. 47 moon (ELP-2000/82 main terms); rise/set at 0.7275*parallax - 34'; transits at hour angle 0/180",
        "toleranceSeconds": TOLERANCE_SECONDS,
        "illuminationTolerance": ILLUMINATION_TOLERANCE,
        "cases": cases,
    }


def ephem_cross_check(fixture: dict) -> int:
    import ephem  # type: ignore

    failures, worst = 0, 0.0
    for case in fixture["cases"]:
        obs = ephem.Observer()
        obs.lat, obs.lon = str(case["latitude"]), str(case["longitude"])
        obs.pressure, obs.horizon = 0, "-0:34"
        moon = ephem.Moon()
        for item in case["events"]:
            t = datetime.fromisoformat(item["time"]).astimezone(timezone.utc)
            obs.date = ephem.Date(t - timedelta(hours=3))
            fn = {"moonrise": obs.next_rising, "moonset": obs.next_setting,
                  "moonTransit": obs.next_transit, "moonLowerTransit": obs.next_antitransit}[item["event"]]
            got = ephem.Date(fn(moon)).datetime().replace(tzinfo=timezone.utc)
            delta = (t - got).total_seconds()
            worst = max(worst, abs(delta))
            flag = "" if abs(delta) <= TOLERANCE_SECONDS else "  <-- exceeds tolerance"
            failures += bool(flag)
            print(f"  {case['name']:<26} {item['event']:<17} {item['time']}  ephem delta {delta:+6.1f}s{flag}")
        noon = datetime.fromisoformat(case["date"] + "T12:00:00").replace(tzinfo=ZoneInfo(case["timeZone"]))
        phase = ephem.Moon(ephem.Date(noon.astimezone(timezone.utc))).phase / 100
        if abs(phase - case["illuminationAtNoon"]) > ILLUMINATION_TOLERANCE:
            failures += 1
            print(f"  {case['name']}: illumination {case['illuminationAtNoon']} vs ephem {phase:.4f}  <-- exceeds tolerance")
    print(f"worst |delta| vs ephem: {worst:.1f}s")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--ephem", action="store_true")
    args = parser.parse_args()
    fixture = build_fixture()
    text = json.dumps(fixture, indent=2) + "\n"
    if args.check:
        if not FIXTURE.exists() or FIXTURE.read_text() != text:
            print(f"{FIXTURE} is stale; run {Path(__file__).name} and commit the result", file=sys.stderr)
            return 1
    else:
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE}")
    if args.ephem:
        return 1 if ephem_cross_check(fixture) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
