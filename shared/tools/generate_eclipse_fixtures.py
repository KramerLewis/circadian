#!/usr/bin/env python3
"""Generate shared/fixtures/eclipse-reference.json.

Reference implementation of the eclipse calculations every platform ports, using the
same sun (NOAA) and moon (Schlyter) models as the other fixtures:

- Lunar eclipses (geocentric): at each full moon, the moon's distance from the center
  of Earth's shadow against the umbra and penumbra radii (Meeus, with the usual 2%
  atmospheric enlargement). Gives type, magnitudes, and contact times.
- Solar eclipses (local): at each new moon, the topocentric separation of the sun and
  moon for the observer against their semidiameters. Gives type, magnitude (fraction
  of the sun's diameter covered), obscuration, and contact times.

--ephem cross-checks the same geometry computed from PyEphem's (accurate) positions.

    python3 shared/tools/generate_eclipse_fixtures.py [--check] [--ephem]
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_solar_fixtures import julian_century  # noqa: E402
from generate_lunar_fixtures import moon_position, hour_angle  # noqa: E402

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "eclipse-reference.json"
TIME_TOLERANCE = 300        # seconds
MAGNITUDE_TOLERANCE = 0.06
R, D = math.radians, math.degrees

LUNAR = ["2025-03-14", "2025-09-07", "2026-03-03", "2026-08-28", "2027-02-20", "2028-01-12"]
SOLAR = [
    ("Seattle, 2017 total eclipse (partial here)", 47.61, -122.33, "2017-08-21"),
    ("Salem OR, 2017 total eclipse", 44.94, -123.03, "2017-08-21"),
    ("Seattle, 2023 annular eclipse (partial here)", 47.61, -122.33, "2023-10-14"),
    ("Dallas, 2024 total eclipse", 32.78, -96.80, "2024-04-08"),
    ("Seattle, 2024 eclipse (partial here)", 47.61, -122.33, "2024-04-08"),
    ("Burgos, 2026 total eclipse", 42.34, -3.70, "2026-08-12"),
]


def sun_position(t: float) -> dict:
    """Apparent geocentric RA/Dec (deg) and distance (AU) of the sun, NOAA formulas."""
    T = julian_century(t)
    l0 = (280.46646 + T * (36000.76983 + 0.0003032 * T)) % 360
    m = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    mr = R(m)
    c = (math.sin(mr) * (1.914602 - T * (0.004817 + 0.000014 * T))
         + math.sin(2 * mr) * (0.019993 - 0.000101 * T) + math.sin(3 * mr) * 0.000289)
    v = m + c
    dist = 1.000001018 * (1 - e * e) / (1 + e * math.cos(R(v)))
    omega = 125.04 - 1934.136 * T
    lam = l0 + c - 0.00569 - 0.00478 * math.sin(R(omega))
    eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
    eps = eps0 + 0.00256 * math.cos(R(omega))
    ra = D(math.atan2(math.cos(R(eps)) * math.sin(R(lam)), math.cos(R(lam)))) % 360
    dec = D(math.asin(math.sin(R(eps)) * math.sin(R(lam))))
    return {"ra": ra, "dec": dec, "distance": dist}


def separation(ra1, dec1, ra2, dec2) -> float:
    """Angular separation in degrees (haversine, accurate for small angles)."""
    a = math.sin(R(dec2 - dec1) / 2) ** 2 + math.cos(R(dec1)) * math.cos(R(dec2)) * math.sin(R(ra2 - ra1) / 2) ** 2
    return D(2 * math.asin(min(1, math.sqrt(a))))


# ---------- lunar ----------

def lunar_geometry(t: float, positions=None) -> tuple[float, float, float, float]:
    """(d, umbra radius, penumbra radius, moon semidiameter) in degrees."""
    sun, moon = positions(t) if positions else (sun_position(t), moon_position(t))
    pm = D(math.asin(1 / moon["distance"]))
    ps = 8.794 / 3600 / sun["distance"]
    ss = 959.63 / 3600 / sun["distance"]
    sm = 0.2725076 * pm
    umbra = 1.02 * (0.99834 * pm - ss + ps)
    penumbra = 1.02 * (0.99834 * pm + ss + ps)
    d = separation((sun["ra"] + 180) % 360, -sun["dec"], moon["ra"], moon["dec"])
    return d, umbra, penumbra, sm


def minimize(f, t0: float, t1: float, step: float) -> float:
    best = min((f(t0 + i * step), t0 + i * step) for i in range(int((t1 - t0) / step) + 1))[1]
    a, b = best - step, best + step
    for _ in range(60):  # golden-section
        m1, m2 = a + (b - a) * 0.382, a + (b - a) * 0.618
        if f(m1) < f(m2):
            b = m2
        else:
            a = m1
    return (a + b) / 2


def crossing(f, a: float, b: float) -> float:
    """f(a) and f(b) have opposite signs."""
    fa = f(a)
    for _ in range(50):
        m = (a + b) / 2
        if (f(m) > 0) == (fa > 0):
            a, fa = m, f(m)
        else:
            b = m
    return (a + b) / 2


def lunar_eclipse(t_full: float, positions=None) -> dict | None:
    g = lambda t: lunar_geometry(t, positions)  # noqa: E731
    greatest = minimize(lambda t: g(t)[0], t_full - 6 * 3600, t_full + 6 * 3600, 600)
    d, u, p, sm = g(greatest)
    umag, pmag = (u + sm - d) / (2 * sm), (p + sm - d) / (2 * sm)
    if pmag <= 0:
        return None
    kind = "total" if d <= u - sm else "partial" if umag > 0 else "penumbral"
    contacts = {}
    for name, radius_of in [("P", lambda u_, p_, s_: p_ + s_), ("U", lambda u_, p_, s_: u_ + s_), ("T", lambda u_, p_, s_: u_ - s_)]:
        h = lambda t: g(t)[0] - radius_of(*g(t)[1:])  # noqa: E731
        if h(greatest) >= 0:
            continue
        contacts[name + "start"] = crossing(h, greatest - 6 * 3600, greatest)
        contacts[name + "end"] = crossing(h, greatest, greatest + 6 * 3600)
    return {"kind": kind, "greatest": greatest, "umbralMagnitude": umag, "penumbralMagnitude": pmag, "contacts": contacts}


# ---------- solar (local) ----------

def solar_geometry(t: float, lat: float, lon: float, positions=None) -> tuple[float, float, float]:
    """(topocentric separation, sun semidiameter, moon semidiameter) in degrees."""
    if positions:
        return positions(t)
    sun, moon = sun_position(t), moon_position(t)
    # Moon vector (Earth radii, equatorial) minus observer vector (spherical Earth).
    r = moon["distance"]
    mx = r * math.cos(R(moon["dec"])) * math.cos(R(moon["ra"]))
    my = r * math.cos(R(moon["dec"])) * math.sin(R(moon["ra"]))
    mz = r * math.sin(R(moon["dec"]))
    lst = moon["ra"] + hour_angle(t, lon, moon["ra"])  # local sidereal time, deg
    ox = math.cos(R(lat)) * math.cos(R(lst))
    oy = math.cos(R(lat)) * math.sin(R(lst))
    oz = math.sin(R(lat))
    tx, ty, tz = mx - ox, my - oy, mz - oz
    tr = math.sqrt(tx * tx + ty * ty + tz * tz)
    ra = D(math.atan2(ty, tx)) % 360
    dec = D(math.asin(tz / tr))
    sm = D(math.asin(0.2725076 / tr))
    ss = 959.63 / 3600 / sun["distance"]
    return separation(sun["ra"], sun["dec"], ra, dec), ss, sm


def obscuration(d: float, ss: float, sm: float) -> float:
    """Fraction of the sun's disc area covered."""
    if d >= ss + sm:
        return 0.0
    if d <= abs(sm - ss):
        return min(1.0, (sm / ss) ** 2)
    a = ss * ss * math.acos((d * d + ss * ss - sm * sm) / (2 * d * ss))
    b = sm * sm * math.acos((d * d + sm * sm - ss * ss) / (2 * d * sm))
    c = 0.5 * math.sqrt((-d + ss + sm) * (d + ss - sm) * (d - ss + sm) * (d + ss + sm))
    return (a + b - c) / (math.pi * ss * ss)


def solar_eclipse(t_new: float, lat: float, lon: float, positions=None) -> dict | None:
    g = lambda t: solar_geometry(t, lat, lon, positions)  # noqa: E731
    maximum = minimize(lambda t: g(t)[0], t_new - 5 * 3600, t_new + 5 * 3600, 120)
    d, ss, sm = g(maximum)
    if d >= ss + sm:
        return None
    kind = "total" if sm > ss and d <= sm - ss else "annular" if sm < ss and d <= ss - sm else "partial"
    outer = lambda t: g(t)[0] - (g(t)[1] + g(t)[2])  # noqa: E731
    result = {
        "kind": kind, "maximum": maximum,
        "magnitude": (ss + sm - d) / (2 * ss), "obscuration": obscuration(d, ss, sm),
        "start": crossing(outer, maximum - 4 * 3600, maximum),
        "end": crossing(outer, maximum, maximum + 4 * 3600),
    }
    if kind != "partial":
        inner = lambda t: g(t)[0] - abs(g(t)[2] - g(t)[1])  # noqa: E731
        result["centralStart"] = crossing(inner, maximum - 3600, maximum)
        result["centralEnd"] = crossing(inner, maximum, maximum + 3600)
    return result


def ts(iso_day: str, hour=12) -> float:
    return datetime.fromisoformat(iso_day + f"T{hour:02d}:00:00+00:00").timestamp()


def iso(t: float) -> str:
    return datetime.fromtimestamp(round(t), timezone.utc).isoformat().replace("+00:00", "Z")


def build_fixture() -> dict:
    lunar = []
    for day in LUNAR:
        # Full moon nearest noon UTC that day (within a day).
        t = minimize(lambda x: lunar_geometry(x)[0], ts(day) - 86400, ts(day) + 86400, 1800)
        e = lunar_eclipse(t)
        lunar.append({"date": day, "kind": e["kind"], "greatest": iso(e["greatest"]),
                      "umbralMagnitude": round(e["umbralMagnitude"], 3), "penumbralMagnitude": round(e["penumbralMagnitude"], 3),
                      "contacts": {k: iso(v) for k, v in sorted(e["contacts"].items())}})
    solar = []
    for name, lat, lon, day in SOLAR:
        t = minimize(lambda x: separation(sun_position(x)["ra"], sun_position(x)["dec"], moon_position(x)["ra"], moon_position(x)["dec"]),
                     ts(day) - 86400, ts(day) + 86400, 1800)
        e = solar_eclipse(t, lat, lon)
        entry = {"name": name, "latitude": lat, "longitude": lon, "date": day}
        if e:
            entry |= {"kind": e["kind"], "maximum": iso(e["maximum"]), "start": iso(e["start"]), "end": iso(e["end"]),
                      "magnitude": round(e["magnitude"], 3), "obscuration": round(e["obscuration"], 3)}
            if "centralStart" in e:
                entry |= {"centralStart": iso(e["centralStart"]), "centralEnd": iso(e["centralEnd"])}
        solar.append(entry)
    return {
        "description": "Reference eclipses for every platform's eclipse calculator tests.",
        "generatedBy": "shared/tools/generate_eclipse_fixtures.py",
        "toleranceSeconds": TIME_TOLERANCE, "magnitudeTolerance": MAGNITUDE_TOLERANCE,
        "lunar": lunar, "solar": solar,
    }


def ephem_cross_check(fixture: dict) -> int:
    import ephem  # type: ignore

    def edate(t):
        return ephem.Date(datetime.fromtimestamp(t, timezone.utc))

    def lunar_positions(t):
        s, m = ephem.Sun(edate(t)), ephem.Moon(edate(t))
        return ({"ra": D(s.g_ra), "dec": D(s.g_dec), "distance": s.earth_distance},
                {"ra": D(m.g_ra), "dec": D(m.g_dec), "distance": m.earth_distance * 149597870.7 / 6378.14})

    failures, worst_t, worst_m = 0, 0.0, 0.0
    for ref in fixture["lunar"]:
        t = datetime.fromisoformat(ref["greatest"].replace("Z", "+00:00")).timestamp()
        e = lunar_eclipse(t, lunar_positions)
        dt = abs(e["greatest"] - t)
        dm = abs(e["umbralMagnitude"] - ref["umbralMagnitude"])
        worst_t, worst_m = max(worst_t, dt), max(worst_m, dm)
        ok = e["kind"] == ref["kind"] and dt <= TIME_TOLERANCE and dm <= MAGNITUDE_TOLERANCE
        failures += not ok
        print(f"  lunar {ref['date']}: {ref['kind']:<9} umbral {ref['umbralMagnitude']:+.3f}  ephem {e['kind']:<9} {e['umbralMagnitude']:+.3f}  Δt {dt:5.0f}s {'' if ok else '<-- mismatch'}")
    for ref in fixture["solar"]:
        obs = ephem.Observer()
        obs.lat, obs.lon, obs.elevation, obs.pressure = str(ref["latitude"]), str(ref["longitude"]), 0, 0

        def positions(t):
            obs.date = edate(t)
            s, m = ephem.Sun(obs), ephem.Moon(obs)
            return D(ephem.separation((s.ra, s.dec), (m.ra, m.dec))), D(s.radius), D(m.radius)

        t0 = ts(ref["date"])
        approx = datetime.fromisoformat(ref["maximum"].replace("Z", "+00:00")).timestamp() if "maximum" in ref else t0
        e = solar_eclipse(approx, ref["latitude"], ref["longitude"], positions)
        if "maximum" not in ref:
            ok = e is None
            print(f"  solar {ref['name']}: none  ephem {'none' if e is None else e['kind']} {'' if ok else '<-- mismatch'}")
        else:
            dt = abs(e["maximum"] - approx)
            dm = abs(e["magnitude"] - ref["magnitude"])
            worst_t, worst_m = max(worst_t, dt), max(worst_m, dm)
            ok = e["kind"] == ref["kind"] and dt <= TIME_TOLERANCE and dm <= MAGNITUDE_TOLERANCE
            print(f"  solar {ref['name']:<46} {ref['kind']:<8} mag {ref['magnitude']:.3f} obsc {ref['obscuration']:.3f}  ephem {e['kind']:<8} {e['magnitude']:.3f} {e['obscuration']:.3f}  Δt {dt:4.0f}s {'' if ok else '<-- mismatch'}")
        failures += not ok
    print(f"worst vs ephem: {worst_t:.0f} s, magnitude {worst_m:.3f}")
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
