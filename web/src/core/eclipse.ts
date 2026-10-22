// Lunar and solar eclipses from the same sun and moon models. A port of ios/SunCore
// EclipseCalculator; tested against shared/fixtures/eclipse-reference.json.

import { hourAngleFor, moonPosition } from "./lunar";
import { type Coordinate, degrees, normalize, radians, rev } from "./math";
import { skyOccurrences } from "./skyCalendar";
import { altitude, solarHourAngle, sunPosition } from "./solar";

// MARK: Lunar

export interface LunarEclipse {
  /** penumbral: a subtle dimming; partial: part of the moon in the umbra; total: a blood moon. */
  kind: "penumbral" | "partial" | "total";
  greatest: number;
  umbralMagnitude: number;
  penumbralMagnitude: number;
  penumbralStart: number;
  penumbralEnd: number;
  partialStart?: number;
  partialEnd?: number;
  totalStart?: number;
  totalEnd?: number;
}

interface LunarGeometry {
  /** Moon center to shadow center, and shadow and moon radii, degrees. */
  separation: number;
  umbra: number;
  penumbra: number;
  moon: number;
}

function lunarGeometry(t: number): LunarGeometry {
  const sun = sunPosition(t);
  const moon = moonPosition(t);
  // Meeus ch. 54, with the customary 2% enlargement for Earth's atmosphere.
  const umbra = 1.02 * (0.99834 * moon.parallax - sun.semidiameter + sun.parallax);
  const penumbra = 1.02 * (0.99834 * moon.parallax + sun.semidiameter + sun.parallax);
  const separation = angularSeparation(rev(sun.rightAscension + 180), -sun.declination, moon.rightAscension, moon.declination);
  return { separation, umbra, penumbra, moon: 0.2725076 * moon.parallax };
}

const hour = 3_600_000;

/** The lunar eclipse at the full moon nearest `fullMoon`, if any. */
export function lunarEclipse(fullMoon: number): LunarEclipse | undefined {
  const greatest = minimize(fullMoon, 6 * hour, 600_000, (t) => lunarGeometry(t).separation);
  const g = lunarGeometry(greatest);
  const umbral = (g.umbra + g.moon - g.separation) / (2 * g.moon);
  const penumbral = (g.penumbra + g.moon - g.separation) / (2 * g.moon);
  if (penumbral <= 0) return undefined;
  const contacts = (radius: (g: LunarGeometry) => number): [number, number] | undefined => {
    const f = (t: number) => {
      const g = lunarGeometry(t);
      return g.separation - radius(g);
    };
    if (f(greatest) >= 0) return undefined;
    return [crossing(f, greatest - 6 * hour, greatest), crossing(f, greatest, greatest + 6 * hour)];
  };
  const whole = contacts((g) => g.penumbra + g.moon);
  if (!whole) return undefined;
  const partial = contacts((g) => g.umbra + g.moon);
  const total = contacts((g) => g.umbra - g.moon);
  return {
    kind: total ? "total" : partial ? "partial" : "penumbral",
    greatest,
    umbralMagnitude: umbral,
    penumbralMagnitude: penumbral,
    penumbralStart: whole[0],
    penumbralEnd: whole[1],
    partialStart: partial?.[0],
    partialEnd: partial?.[1],
    totalStart: total?.[0],
    totalEnd: total?.[1],
  };
}

/** How far into Earth's inner shadow the moon is: 0 outside, 1 wholly inside. */
export function umbralCoverage(t: number): number {
  const g = lunarGeometry(t);
  return Math.min(Math.max((g.umbra + g.moon - g.separation) / (2 * g.moon), 0), 1);
}

// MARK: Solar (local)

export interface SolarEclipse {
  kind: "partial" | "annular" | "total";
  start: number;
  maximum: number;
  end: number;
  /** Fraction of the sun's diameter covered at maximum. */
  magnitude: number;
  /** Fraction of the sun's area covered at maximum. */
  obscuration: number;
  /** Totality or the annular ring, when the location gets one. */
  centralStart?: number;
  centralEnd?: number;
  sunAltitudeAtMaximum: number;
}

interface SolarGeometry {
  /** Topocentric sun-moon separation and semidiameters, degrees; side +1 when the moon is east. */
  separation: number;
  sun: number;
  moon: number;
  side: number;
}

function solarGeometry(t: number, coordinate: Coordinate): SolarGeometry {
  const sun = sunPosition(t);
  const moon = moonPosition(t);
  // Topocentric moon: its geocentric vector (Earth radii) minus the observer's.
  const r = moon.distance;
  const mra = radians(moon.rightAscension), mdec = radians(moon.declination);
  const mx = r * Math.cos(mdec) * Math.cos(mra), my = r * Math.cos(mdec) * Math.sin(mra), mz = r * Math.sin(mdec);
  const lst = radians(moon.rightAscension + hourAngleFor(t, coordinate.longitude, moon.rightAscension));
  const lat = radians(coordinate.latitude);
  const tx = mx - Math.cos(lat) * Math.cos(lst), ty = my - Math.cos(lat) * Math.sin(lst), tz = mz - Math.sin(lat);
  const tr = Math.hypot(tx, ty, tz);
  const ra = rev(degrees(Math.atan2(ty, tx)));
  const dec = degrees(Math.asin(tz / tr));
  return {
    separation: angularSeparation(sun.rightAscension, sun.declination, ra, dec),
    sun: sun.semidiameter,
    moon: degrees(Math.asin(0.2725076 / tr)),
    side: normalize(ra - sun.rightAscension) >= 0 ? 1 : -1,
  };
}

function obscuration(g: SolarGeometry): number {
  const d = g.separation, ss = g.sun, sm = g.moon;
  if (d >= ss + sm) return 0;
  if (d <= Math.abs(sm - ss)) return Math.min(1, (sm / ss) ** 2);
  const a = ss * ss * Math.acos((d * d + ss * ss - sm * sm) / (2 * d * ss));
  const b = sm * sm * Math.acos((d * d + sm * sm - ss * ss) / (2 * d * sm));
  const c = 0.5 * Math.sqrt((-d + ss + sm) * (d + ss - sm) * (d - ss + sm) * (d + ss + sm));
  return (a + b - c) / (Math.PI * ss * ss);
}

/** The solar eclipse seen from `coordinate` at the new moon nearest `newMoon`, if any. */
export function solarEclipse(newMoon: number, coordinate: Coordinate): SolarEclipse | undefined {
  const geometry = (t: number) => solarGeometry(t, coordinate);
  const maximum = minimize(newMoon, 5 * hour, 120_000, (t) => geometry(t).separation);
  const g = geometry(maximum);
  if (g.separation >= g.sun + g.moon) return undefined;
  const kind =
    g.moon > g.sun && g.separation <= g.moon - g.sun ? "total"
    : g.moon < g.sun && g.separation <= g.sun - g.moon ? "annular"
    : "partial";
  const outer = (t: number) => {
    const g = geometry(t);
    return g.separation - (g.sun + g.moon);
  };
  const inner = (t: number) => {
    const g = geometry(t);
    return g.separation - Math.abs(g.moon - g.sun);
  };
  const central = kind === "partial" ? undefined : [crossing(inner, maximum - hour, maximum), crossing(inner, maximum, maximum + hour)];
  return {
    kind,
    start: crossing(outer, maximum - 4 * hour, maximum),
    maximum,
    end: crossing(outer, maximum, maximum + 4 * hour),
    magnitude: (g.sun + g.moon - g.separation) / (2 * g.sun),
    obscuration: obscuration(g),
    centralStart: central?.[0],
    centralEnd: central?.[1],
    sunAltitudeAtMaximum: altitude(
      solarHourAngle(maximum, coordinate.longitude),
      coordinate.latitude,
      sunPosition(maximum).declination,
    ),
  };
}

/** How much of the sun the moon covers now, and where it sits, for drawing. */
export function solarCoverage(t: number, coordinate: Coordinate): { obscuration: number; offset: number; moonScale: number } {
  const g = solarGeometry(t, coordinate);
  return { obscuration: obscuration(g), offset: (g.separation / g.sun) * g.side, moonScale: g.moon / g.sun };
}

// MARK: Searching

export function lunarEclipses(start: number, end: number): LunarEclipse[] {
  return skyOccurrences(start, end, "UTC")
    .filter((o) => o.kind.type === "fullMoon")
    .map((o) => lunarEclipse(o.date))
    .filter((e): e is LunarEclipse => !!e);
}

/** Solar eclipses seen from `coordinate` (including ones below the horizon). */
export function solarEclipses(start: number, end: number, coordinate: Coordinate): SolarEclipse[] {
  return skyOccurrences(start, end, "UTC")
    .filter((o) => o.kind.type === "newMoon")
    // Only new moons near a node can eclipse the sun.
    .filter((o) => Math.abs(moonPosition(o.date).latitude) < 1.6)
    .map((o) => solarEclipse(o.date, coordinate))
    .filter((e): e is SolarEclipse => !!e);
}

// MARK: Helpers

function angularSeparation(ra1: number, dec1: number, ra2: number, dec2: number): number {
  const a =
    Math.sin(radians(dec2 - dec1) / 2) ** 2 +
    Math.cos(radians(dec1)) * Math.cos(radians(dec2)) * Math.sin(radians(ra2 - ra1) / 2) ** 2;
  return degrees(2 * Math.asin(Math.min(1, Math.sqrt(a))));
}

/** The time near `center` (within `span`) minimizing `f`: a coarse scan, then golden-section search. */
function minimize(center: number, span: number, step: number, f: (t: number) => number): number {
  let best = center - span, bestValue = Infinity;
  for (let t = center - span; t <= center + span; t += step) {
    const v = f(t);
    if (v < bestValue) {
      best = t;
      bestValue = v;
    }
  }
  let a = best - step, b = best + step;
  for (let i = 0; i < 60; i++) {
    const m1 = a + (b - a) * 0.382, m2 = a + (b - a) * 0.618;
    if (f(m1) < f(m2)) b = m2;
    else a = m1;
  }
  return (a + b) / 2;
}

/** Where `f` changes sign between `a` and `b`. */
function crossing(f: (t: number) => number, a: number, b: number): number {
  let lo = a, hi = b;
  const negativeAtLo = f(a) < 0;
  for (let i = 0; i < 50; i++) {
    const mid = (lo + hi) / 2;
    if (f(mid) < 0 === negativeAtLo) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}
