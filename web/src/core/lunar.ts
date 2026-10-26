// The moon's position, phase and daily events. A port of ios/SunCore LunarCalculator;
// tested against shared/fixtures/lunar-reference.json.
//
// Position uses the main terms of ELP-2000/82 as given by Meeus, *Astronomical
// Algorithms* ch. 47. Rise/set use the altitude 0.7275 * parallax - 34'.

import { latitudeTerms, longitudeDistanceTerms } from "./lunarTerms";
import { type Coordinate, degrees, normalize, radians, rev } from "./math";
import { altitude, sunPosition } from "./solar";

export type LunarEvent = "moonrise" | "moonTransit" | "moonset" | "moonLowerTransit";

export const lunarEventNames: Record<LunarEvent, string> = {
  moonrise: "Moonrise",
  moonTransit: "Moon highest",
  moonset: "Moonset",
  moonLowerTransit: "Moon lowest",
};

export interface MoonPosition {
  /** Geocentric ecliptic longitude and latitude, degrees. */
  longitude: number;
  latitude: number;
  /** Geocentric right ascension and declination, degrees. */
  rightAscension: number;
  declination: number;
  /** Earth radii. */
  distance: number;
  /** Horizontal parallax, degrees. */
  parallax: number;
}

export interface Phase {
  /** Illuminated fraction, 0 (new) to 1 (full). */
  illumination: number;
  isWaxing: boolean;
}

export interface LunarOccurrence {
  event: LunarEvent;
  date: number;
}

/** TT − UT, seconds: within a second of 69 s since 2015. */
export const deltaT = 69;
export const earthRadiusKm = 6378.14;

export function moonPosition(instant: number): MoonPosition {
  const jd = (instant / 1000 + deltaT) / 86_400 + 2_440_587.5;
  const t = (jd - 2_451_545) / 36_525;
  const t2 = t * t, t3 = t2 * t, t4 = t3 * t;

  const lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538_841 - t4 / 65_194_000;
  const d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545_868 - t4 / 113_065_000;
  const m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24_490_000;
  const mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69_699 - t4 / 14_712_000;
  const f = 93.272095 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3_526_000 + t4 / 863_310_000;
  const a1 = 119.75 + 131.849 * t;
  const a2 = 53.09 + 479264.29 * t;
  const a3 = 313.45 + 481266.484 * t;
  const e = 1 - 0.002516 * t - 0.0000074 * t2;

  const argument = (cd: number, cm: number, cmp: number, cf: number) => radians(cd * d + cm * m + cmp * mp + cf * f);
  const eccentricity = (cm: number) => (cm === 0 ? 1 : Math.abs(cm) === 1 ? e : e * e);

  let sl = 0, sr = 0, sb = 0;
  for (const [cd, cm, cmp, cf, l, r] of longitudeDistanceTerms) {
    const arg = argument(cd, cm, cmp, cf);
    const ecc = eccentricity(cm);
    sl += l * ecc * Math.sin(arg);
    sr += r * ecc * Math.cos(arg);
  }
  for (const [cd, cm, cmp, cf, b] of latitudeTerms) {
    sb += b * eccentricity(cm) * Math.sin(argument(cd, cm, cmp, cf));
  }
  sl += 3958 * Math.sin(radians(a1)) + 1962 * Math.sin(radians(lp - f)) + 318 * Math.sin(radians(a2));
  sb +=
    -2235 * Math.sin(radians(lp)) + 382 * Math.sin(radians(a3)) + 175 * Math.sin(radians(a1 - f)) +
    175 * Math.sin(radians(a1 + f)) + 127 * Math.sin(radians(lp - mp)) - 115 * Math.sin(radians(lp + mp));

  // Nutation (main terms) and the true obliquity of the ecliptic.
  const omega = radians(125.04452 - 1934.136261 * t);
  const ls = radians(280.4665 + 36000.7698 * t), lm = radians(218.3165 + 481267.8813 * t);
  const dpsi = (-17.2 * Math.sin(omega) - 1.32 * Math.sin(2 * ls) - 0.23 * Math.sin(2 * lm) + 0.21 * Math.sin(2 * omega)) / 3600;
  const deps = (9.2 * Math.cos(omega) + 0.57 * Math.cos(2 * ls) + 0.1 * Math.cos(2 * lm) - 0.09 * Math.cos(2 * omega)) / 3600;
  const eps0 = 23 + 26 / 60 + 21.448 / 3600 - (46.815 * t + 0.00059 * t2 - 0.001813 * t3) / 3600;
  const eps = radians(eps0 + deps);

  const lon = rev(lp + sl / 1e6 + dpsi);
  const lat = sb / 1e6;
  const distanceKm = 385_000.56 + sr / 1000;
  const l = radians(lon), b = radians(lat);
  const ra = rev(degrees(Math.atan2(Math.sin(l) * Math.cos(eps) - Math.tan(b) * Math.sin(eps), Math.cos(l))));
  const dec = degrees(Math.asin(Math.sin(b) * Math.cos(eps) + Math.cos(b) * Math.sin(eps) * Math.sin(l)));
  const distance = distanceKm / earthRadiusKm;
  return { longitude: lon, latitude: lat, rightAscension: ra, declination: dec, distance, parallax: degrees(Math.asin(1 / distance)) };
}

/** Greenwich mean sidereal time, degrees: how far Earth has turned under the stars. */
export function siderealTime(instant: number): number {
  const jd = instant / 86_400_000 + 2_440_587.5;
  const t = (jd - 2_451_545) / 36_525;
  return 280.46061837 + 360.98564736629 * (jd - 2_451_545) + 0.000387933 * t * t;
}

/** Local hour angle of a body with right ascension `ra`, in (-180, 180]. */
export function hourAngleFor(instant: number, longitude: number, ra: number): number {
  return normalize(siderealTime(instant) + longitude - ra);
}

export function moonHourAngle(instant: number, longitude: number): number {
  return hourAngleFor(instant, longitude, moonPosition(instant).rightAscension);
}

export function moonAltitude(instant: number, coordinate: Coordinate): number {
  const p = moonPosition(instant);
  return altitude(hourAngleFor(instant, coordinate.longitude, p.rightAscension), coordinate.latitude, p.declination);
}

/** Altitude of the moon's center at moonrise/moonset. */
export function riseSetAltitude(distance: number): number {
  return 0.7275 * degrees(Math.asin(1 / distance)) - 34 / 60;
}

export function moonPhase(instant: number): Phase {
  const moon = moonPosition(instant);
  const sunLongitude = sunPosition(instant).apparentLongitude;
  const elongation = degrees(Math.acos(Math.cos(radians(moon.latitude)) * Math.cos(radians(moon.longitude - sunLongitude))));
  return { illumination: (1 - Math.cos(radians(elongation))) / 2, isWaxing: rev(moon.longitude - sunLongitude) < 180 };
}

export function phaseName(phase: Phase): string {
  const k = phase.illumination;
  if (k < 0.02) return "New moon";
  if (k >= 0.98) return "Full moon";
  if (k >= 0.45 && k < 0.55) return phase.isWaxing ? "First quarter" : "Last quarter";
  if (k < 0.45) return phase.isWaxing ? "Waxing crescent" : "Waning crescent";
  return phase.isWaxing ? "Waxing gibbous" : "Waning gibbous";
}

const step = 600_000;

/** Moonrise, moonset and both transits in [start, end), chronological. */
export function lunarEvents(start: number, end: number, coordinate: Coordinate): LunarOccurrence[] {
  const lon = coordinate.longitude;
  const aboveHorizon = (t: number) => {
    const p = moonPosition(t);
    return altitude(hourAngleFor(t, lon, p.rightAscension), coordinate.latitude, p.declination) - riseSetAltitude(p.distance);
  };
  const upper = (t: number) => moonHourAngle(t, lon);
  const lower = (t: number) => normalize(upper(t) - 180);

  const found: LunarOccurrence[] = [];
  let t = start;
  let previous = [aboveHorizon(t), upper(t), lower(t)];
  while (t < end) {
    const next = Math.min(t + step, end);
    const current = [aboveHorizon(next), upper(next), lower(next)];
    if (previous[0] < 0 && current[0] >= 0) found.push({ event: "moonrise", date: bisect(aboveHorizon, t, next) });
    if (previous[0] >= 0 && current[0] < 0) found.push({ event: "moonset", date: bisect(aboveHorizon, t, next) });
    // An hour-angle crossing of 0 (not the wrap at 180) is a transit.
    if (previous[1] < 0 && current[1] >= 0 && current[1] - previous[1] < 90) {
      found.push({ event: "moonTransit", date: bisect(upper, t, next) });
    }
    if (previous[2] < 0 && current[2] >= 0 && current[2] - previous[2] < 90) {
      found.push({ event: "moonLowerTransit", date: bisect(lower, t, next) });
    }
    t = next;
    previous = current;
  }
  return found.sort((a, b) => a.date - b.date);
}

function bisect(f: (t: number) => number, a: number, b: number): number {
  let fa = f(a);
  for (let i = 0; i < 30; i++) {
    const mid = (a + b) / 2;
    const fm = f(mid);
    if (fm > 0 === fa > 0) {
      a = mid;
      fa = fm;
    } else {
      b = mid;
    }
  }
  return (a + b) / 2;
}
