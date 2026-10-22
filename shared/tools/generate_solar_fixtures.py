#!/usr/bin/env python3
"""Generate shared/fixtures/solar-reference.json.

This is a reference port of the NOAA solar calculator (Meeus-based formulas from
https://gml.noaa.gov/grad/solcalc/calcdetails.html), using the same instant-based
iteration every platform implementation uses. Each platform's test suite checks
its own implementation against the JSON this script writes.

Usage:
    python3 shared/tools/generate_solar_fixtures.py            # write the fixture
    python3 shared/tools/generate_solar_fixtures.py --check    # fail if the fixture is stale
    python3 shared/tools/generate_solar_fixtures.py --ephem    # also cross-check against PyEphem

The --ephem cross-check needs `pip install ephem` (an independent VSOP87-based
ephemeris). It only runs when asked, so the generator itself has no dependencies.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "solar-reference.json"
TOLERANCE_SECONDS = 60

# Sun altitude (degrees) at each horizon event. Sunrise/sunset use the standard
# -0.833 deg (refraction + solar semidiameter).
ALTITUDES = {
    "astronomical": -18.0,
    "nautical": -12.0,
    "civil": -6.0,
    "sun": -0.833,
}

EVENTS = [
    # (name, altitude key or None, direction) direction: -1 morning, +1 evening
    ("solarMidnight", None, 0),
    ("astronomicalDawn", "astronomical", -1),
    ("nauticalDawn", "nautical", -1),
    ("civilDawn", "civil", -1),
    ("sunrise", "sun", -1),
    ("solarNoon", None, 0),
    ("sunset", "sun", 1),
    ("civilDusk", "civil", 1),
    ("nauticalDusk", "nautical", 1),
    ("astronomicalDusk", "astronomical", 1),
]

CASES = [
    # Seattle: both solstices, the March equinox, both 2026 DST transitions.
    ("Seattle, DST begins", 47.61, -122.33, "America/Los_Angeles", "2026-03-08"),
    ("Seattle, March equinox", 47.61, -122.33, "America/Los_Angeles", "2026-03-20"),
    ("Seattle, June solstice", 47.61, -122.33, "America/Los_Angeles", "2026-06-21"),
    ("Seattle, DST ends", 47.61, -122.33, "America/Los_Angeles", "2026-11-01"),
    ("Seattle, December solstice", 47.61, -122.33, "America/Los_Angeles", "2026-12-21"),
    # Polar edge cases.
    ("Tromso, midnight sun", 69.65, 18.96, "Europe/Oslo", "2026-06-21"),
    ("Tromso, polar night", 69.65, 18.96, "Europe/Oslo", "2026-12-21"),
    ("Longyearbyen, polar night", 78.22, 15.65, "Arctic/Longyearbyen", "2026-12-21"),
    # Southern hemisphere, east longitude.
    ("Sydney, June solstice", -33.87, 151.21, "Australia/Sydney", "2026-06-21"),
]


# --- NOAA solar position ------------------------------------------------------

def julian_century(t: float) -> float:
    """t is Unix seconds."""
    jd = t / 86400.0 + 2440587.5
    return (jd - 2451545.0) / 36525.0


def sun_position(t: float) -> tuple[float, float]:
    """Return (declination degrees, equation of time minutes) at Unix time t."""
    T = julian_century(t)
    l0 = (280.46646 + T * (36000.76983 + 0.0003032 * T)) % 360.0
    m = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    mr = math.radians(m)
    c = (
        math.sin(mr) * (1.914602 - T * (0.004817 + 0.000014 * T))
        + math.sin(2 * mr) * (0.019993 - 0.000101 * T)
        + math.sin(3 * mr) * 0.000289
    )
    true_long = l0 + c
    omega = 125.04 - 1934.136 * T
    app_long = true_long - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    seconds = 21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))
    mean_obliq = 23.0 + (26.0 + seconds / 60.0) / 60.0
    obliq = mean_obliq + 0.00256 * math.cos(math.radians(omega))
    dec = math.degrees(math.asin(math.sin(math.radians(obliq)) * math.sin(math.radians(app_long))))
    y = math.tan(math.radians(obliq) / 2) ** 2
    l0r = math.radians(l0)
    eot = (
        y * math.sin(2 * l0r)
        - 2 * e * math.sin(mr)
        + 4 * e * y * math.sin(mr) * math.cos(2 * l0r)
        - 0.5 * y * y * math.sin(4 * l0r)
        - 1.25 * e * e * math.sin(2 * mr)
    )
    return dec, 4.0 * math.degrees(eot)


def normalize_degrees(d: float) -> float:
    """Wrap to (-180, 180]."""
    d = math.fmod(d, 360.0)
    if d <= -180.0:
        d += 360.0
    elif d > 180.0:
        d -= 360.0
    return d


def hour_angle(t: float, longitude: float) -> float:
    """Solar hour angle in degrees, (-180, 180], 0 at solar noon."""
    _, eot = sun_position(t)
    utc_minutes = (t / 60.0) % 1440.0
    apparent_solar_minutes = (utc_minutes + 4.0 * longitude + eot) % 1440.0
    return normalize_degrees((apparent_solar_minutes - 720.0) / 4.0)


def solve_hour_angle(target: float, start: float, longitude: float) -> float:
    """Instant nearest `start` at which the hour angle equals `target`."""
    t = start
    for _ in range(5):
        t += normalize_degrees(target - hour_angle(t, longitude)) * 240.0
    return t


def altitude_hour_angle(altitude: float, latitude: float, declination: float) -> float | str:
    lat = math.radians(max(-89.9999, min(89.9999, latitude)))
    dec = math.radians(declination)
    cos_h = (math.sin(math.radians(altitude)) - math.sin(lat) * math.sin(dec)) / (math.cos(lat) * math.cos(dec))
    if cos_h > 1.0:
        return "sunAlwaysBelow"
    if cos_h < -1.0:
        return "sunAlwaysAbove"
    return math.degrees(math.acos(cos_h))


def solar_day(latitude: float, longitude: float, tz: ZoneInfo, day: date) -> dict[str, float | str]:
    local_noon = datetime.combine(day, time(12, 0), tzinfo=tz).timestamp()
    noon = solve_hour_angle(0.0, local_noon, longitude)
    results: dict[str, float | str] = {
        "solarNoon": noon,
        "solarMidnight": solve_hour_angle(180.0, noon - 43200.0, longitude),
    }
    for name, key, direction in EVENTS:
        if key is None:
            continue
        altitude = ALTITUDES[key]
        dec, _ = sun_position(noon)
        h = altitude_hour_angle(altitude, latitude, dec)
        if isinstance(h, str):
            results[name] = h
            continue
        t = noon + direction * h * 240.0
        outcome: float | str = t
        for _ in range(5):
            dec, _ = sun_position(t)
            h = altitude_hour_angle(altitude, latitude, dec)
            if isinstance(h, str):
                outcome = h
                break
            t += normalize_degrees(direction * h - hour_angle(t, longitude)) * 240.0
            outcome = t
        results[name] = outcome
    return results


# --- Fixture ------------------------------------------------------------------

def build_fixture() -> dict:
    cases = []
    for name, lat, lon, tz_name, day in CASES:
        tz = ZoneInfo(tz_name)
        values = solar_day(lat, lon, tz, date.fromisoformat(day))
        events = {}
        for event, _, _ in EVENTS:
            v = values[event]
            if isinstance(v, str):
                events[event] = v
            else:
                events[event] = datetime.fromtimestamp(round(v), tz).isoformat()
        cases.append(
            {
                "name": name,
                "latitude": lat,
                "longitude": lon,
                "timeZone": tz_name,
                "date": day,
                "events": events,
            }
        )
    return {
        "description": "Reference solar event times for every platform's solar calculator tests.",
        "generatedBy": "shared/tools/generate_solar_fixtures.py",
        "algorithm": "NOAA solar calculator (Meeus); sunrise/sunset at -0.833 deg altitude",
        "toleranceSeconds": TOLERANCE_SECONDS,
        "eventValues": "ISO 8601 local time, or 'sunAlwaysAbove' / 'sunAlwaysBelow' when the sun never crosses that altitude",
        "cases": cases,
    }


def ephem_cross_check(fixture: dict) -> int:
    import ephem  # type: ignore

    sun = ephem.Sun()
    worst = 0.0
    failures = 0
    for case in fixture["cases"]:
        obs = ephem.Observer()
        obs.lat, obs.lon = str(case["latitude"]), str(case["longitude"])
        obs.pressure = 0  # we model refraction through the -0.833 deg horizon
        for event, key, direction in EVENTS:
            expected = case["events"][event]
            if expected in ("sunAlwaysAbove", "sunAlwaysBelow"):
                # The sun must never cross this altitude during the day.
                obs.horizon = str(ALTITUDES[key])
                obs.date = ephem.Date(datetime.fromisoformat(case["events"]["solarNoon"]).astimezone(timezone.utc))
                try:
                    obs.next_rising(sun, use_center=True)
                    agrees = False
                except ephem.AlwaysUpError:
                    agrees = expected == "sunAlwaysAbove"
                except ephem.NeverUpError:
                    agrees = expected == "sunAlwaysBelow"
                if not agrees:
                    failures += 1
                print(f"  {case['name']:<28} {event:<17} NOAA {expected:<25}  ephem {'agrees' if agrees else 'DISAGREES'}")
                continue
            t = datetime.fromisoformat(expected).astimezone(timezone.utc)
            obs.date = ephem.Date(t - timedelta(hours=6))
            try:
                if key is None:
                    fn = obs.next_transit if event == "solarNoon" else obs.next_antitransit
                    got = fn(sun)
                else:
                    # All our altitudes are for the sun's center.
                    obs.horizon = str(ALTITUDES[key])
                    fn = obs.next_rising if direction < 0 else obs.next_setting
                    got = fn(sun, use_center=True)
            except ephem.CircumpolarError:
                print(f"  {case['name']}: {event}: ephem says circumpolar, NOAA says {expected}")
                failures += 1
                continue
            got_dt = ephem.Date(got).datetime().replace(tzinfo=timezone.utc)
            delta = (got_dt - t).total_seconds()
            worst = max(worst, abs(delta))
            flag = "" if abs(delta) <= TOLERANCE_SECONDS else "  <-- exceeds tolerance"
            if flag:
                failures += 1
            print(f"  {case['name']:<28} {event:<17} NOAA {expected}  ephem delta {delta:+6.1f}s{flag}")
    print(f"worst |delta| vs ephem: {worst:.1f}s")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the fixture on disk is stale")
    parser.add_argument("--ephem", action="store_true", help="cross-check against PyEphem")
    args = parser.parse_args()

    fixture = build_fixture()
    text = json.dumps(fixture, indent=2) + "\n"
    if args.check:
        if not FIXTURE.exists() or FIXTURE.read_text() != text:
            print(f"{FIXTURE} is stale; run {Path(__file__).name} and commit the result", file=sys.stderr)
            return 1
    else:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE}")
    if args.ephem:
        return 1 if ephem_cross_check(fixture) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
