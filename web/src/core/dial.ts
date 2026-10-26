// Dial geometry and sky colors, independent of drawing. A port of ios/SunCore DialModel,
// SkyGradient, MoonDialModel and MoonGradient.
//
// Angles are degrees clockwise from the top, in (-180, 180]: the sun's hour angle, so
// solar noon is at the top and solar midnight at the bottom.

import { hourAngleFor, lunarEvents, moonAltitude, moonPhase, moonPosition, type Phase, riseSetAltitude } from "./lunar";
import type { Coordinate } from "./math";
import { type SolarDay, type SolarEvent, altitude, isInstant, solarDayContaining, solarEvents, solarHourAngle, sunPosition } from "./solar";

export interface Marker {
  event: SolarEvent;
  date: number;
  angle: number;
}

export interface DialModel {
  markers: Marker[];
  nowAngle: number;
  latitude: number;
  /** The sun's declination at this day's solar noon. */
  declination: number;
}

export function dialModel(day: SolarDay, now: number): DialModel {
  const lon = day.coordinate.longitude;
  const markers: Marker[] = [];
  for (const event of solarEvents) {
    const time = day.events[event];
    if (isInstant(time)) markers.push({ event, date: time, angle: solarHourAngle(time, lon) });
  }
  return {
    markers,
    nowAngle: solarHourAngle(now, lon),
    latitude: day.coordinate.latitude,
    declination: sunPosition(day.solarNoon).declination,
  };
}

/** The sun's altitude at a dial angle. */
export function dialAltitude(model: { latitude: number; declination: number }, angle: number): number {
  return altitude(angle, model.latitude, model.declination);
}

/** Dial angle of a solar clock hour (0-24): 12 is the top, 0 the bottom. */
export const angleForSolarHour = (hour: number): number => hour * 15 - 180;

// MARK: Sky colors

export type RGB = [number, number, number];

const lightStops: [number, RGB][] = [
  [-18, [0.1, 0.12, 0.26]],
  [-12, [0.18, 0.21, 0.42]],
  [-6, [0.33, 0.37, 0.66]],
  [-2.5, [0.74, 0.52, 0.66]],
  [-0.833, [0.96, 0.52, 0.36]],
  [4, [1.0, 0.64, 0.3]],
  [12, [1.0, 0.78, 0.4]],
  [30, [1.0, 0.87, 0.5]],
  [55, [1.0, 0.94, 0.66]],
  [75, [1.0, 0.98, 0.84]],
];

const darkStops: [number, RGB][] = [
  [-18, [0.05, 0.06, 0.15]],
  [-12, [0.1, 0.12, 0.28]],
  [-6, [0.21, 0.25, 0.48]],
  [-2.5, [0.52, 0.36, 0.5]],
  [-0.833, [0.8, 0.4, 0.26]],
  [4, [0.88, 0.5, 0.22]],
  [12, [0.9, 0.63, 0.28]],
  [30, [0.92, 0.72, 0.36]],
  [55, [0.95, 0.8, 0.48]],
  [75, [0.97, 0.86, 0.62]],
];

/** Indices of the stops around `x` and the fraction between them; clamps at the ends. */
function bracket(x: number, positions: number[]): [number, number, number] {
  if (!(x > positions[0])) return [0, 0, 0];
  const upper = positions.findIndex((p) => p >= x);
  if (upper < 0) return [positions.length - 1, positions.length - 1, 0];
  const lower = upper - 1;
  return [lower, upper, (x - positions[lower]) / (positions[upper] - positions[lower])];
}

const mix = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

export function skyColor(alt: number, dark: boolean): RGB {
  const stops = dark ? darkStops : lightStops;
  const [lo, hi, t] = bracket(alt, stops.map((s) => s[0]));
  return mix(stops[lo][1], stops[hi][1], t);
}

/** (altitude, core, glow) */
const sunStops: [number, RGB, RGB][] = [
  [-2, [1.0, 0.35, 0.15], [1.0, 0.3, 0.12]],
  [0, [1.0, 0.45, 0.18], [1.0, 0.38, 0.15]],
  [3, [1.0, 0.62, 0.28], [1.0, 0.5, 0.2]],
  [8, [1.0, 0.78, 0.45], [1.0, 0.62, 0.25]],
  [20, [1.0, 0.9, 0.68], [1.0, 0.74, 0.35]],
  [45, [1.0, 0.97, 0.88], [1.0, 0.84, 0.5]],
];

/** The sun's color at an altitude: white-gold high up, red at the horizon. */
export function sunColor(alt: number): { core: RGB; glow: RGB } {
  const [lo, hi, t] = bracket(alt, sunStops.map((s) => s[0]));
  return { core: mix(sunStops[lo][1], sunStops[hi][1], t), glow: mix(sunStops[lo][2], sunStops[hi][2], t) };
}

// MARK: Moon ring

export interface MoonMarker {
  event: "moonrise" | "moonset";
  date: number;
  angle: number;
}

/**
 * The moon ring, on the sun ring's timeline: the dial angle is the sun's hour angle, so
 * the moon sits under the "now" hand and its rise and set land at their clock times.
 */
export interface MoonDialModel {
  latitude: number;
  /** The current dial angle (the same as the sun's hand). */
  nowAngle: number;
  altitudeNow: number;
  riseSetAltitude: number;
  phase: Phase;
  /** Moonrise and moonset during this solar day, chronological. */
  horizonMarkers: MoonMarker[];
  /** The moon's altitude every 2 degrees of the dial, from -180 to 180. */
  samples: number[];
  /**
   * Where the moon is in the sky, for the "in the sky" view: its own hour angle, so its
   * angle from the sun on the dial is its angle from the sun in the sky (which sets the
   * phase). Rise and set are where it crosses the horizon, with their next clock times.
   */
  sky: {
    nowAngle: number;
    declination: number;
    riseSetAngle?: number;
    nextRise?: number;
    nextSet?: number;
  };
}

const moonStep = 2;

export function moonDialModel(now: number, coordinate: Coordinate): MoonDialModel {
  const day = solarDayContaining(now, coordinate);
  // The instant at each dial angle: solar midnight at -180, noon at 0, the next at 180.
  const instant = (angle: number) =>
    day.solarNoon + (angle / 180) * (angle < 0 ? day.solarNoon - day.solarMidnight : day.nextSolarMidnight - day.solarNoon);
  const count = 360 / moonStep;
  const samples = Array.from({ length: count + 1 }, (_, i) => moonAltitude(instant(-180 + i * moonStep), coordinate));
  const rsa = riseSetAltitude(moonPosition(now).distance);
  // Rise and set where the samples cross the rise/set altitude; a straight line between
  // samples 8 minutes apart is within a minute or so of the full event search.
  const horizonMarkers: MoonMarker[] = [];
  for (let i = 0; i < count; i++) {
    const a = samples[i] - rsa, b = samples[i + 1] - rsa;
    if (a < 0 === b < 0) continue;
    const angle = -180 + (i + a / (a - b)) * moonStep;
    horizonMarkers.push({ event: a < 0 ? "moonrise" : "moonset", date: instant(angle), angle });
  }
  const position = moonPosition(now);
  const lat = (coordinate.latitude * Math.PI) / 180, dec = (position.declination * Math.PI) / 180;
  const cosH = (Math.sin((rsa * Math.PI) / 180) - Math.sin(lat) * Math.sin(dec)) / (Math.cos(lat) * Math.cos(dec));
  const upcoming = lunarEvents(now, now + 30 * 3_600_000, coordinate);
  return {
    sky: {
      nowAngle: hourAngleFor(now, coordinate.longitude, position.rightAscension),
      declination: position.declination,
      riseSetAngle: cosH >= -1 && cosH <= 1 ? (Math.acos(cosH) * 180) / Math.PI : undefined,
      nextRise: upcoming.find((e) => e.event === "moonrise")?.date,
      nextSet: upcoming.find((e) => e.event === "moonset")?.date,
    },
    latitude: coordinate.latitude,
    nowAngle: solarHourAngle(now, coordinate.longitude),
    altitudeNow: moonAltitude(now, coordinate),
    riseSetAltitude: rsa,
    phase: moonPhase(now),
    horizonMarkers,
    samples,
  };
}

/** The moon's altitude at a dial angle during this solar day. */
export function moonAltitudeAt(model: MoonDialModel, angle: number): number {
  const a = (((angle + 180) % 360) + 360) % 360;
  const x = a / moonStep;
  const i = Math.min(Math.floor(x), model.samples.length - 2);
  const t = x - i;
  return model.samples[i] * (1 - t) + model.samples[i + 1] * t;
}

/** Moon ring colors: dark while the moon is down, silver while it's up. */
export function moonRingColor(alt: number, riseSetAlt: number, illumination: number, dark: boolean): RGB {
  const down: RGB = dark ? [0.1, 0.11, 0.17] : [0.2, 0.22, 0.32];
  const up: RGB = dark ? [0.8, 0.84, 0.94] : [0.86, 0.89, 0.97];
  const height = Math.min(Math.max((alt - riseSetAlt) / 30, 0), 1);
  const horizonFade = Math.min(Math.max((alt - riseSetAlt + 1) / 3, 0), 1);
  const t = horizonFade * (0.35 + 0.65 * height) * (0.25 + 0.75 * illumination);
  return mix(down, up, t);
}
