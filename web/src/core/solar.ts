// Solar position and event times with the NOAA solar calculator formulas (Meeus).
// A port of ios/SunCore SolarCalculator; tested against shared/fixtures/solar-reference.json.
//
// Every event is solved as an instant rather than as minutes past a UTC date, so time
// zones only matter for choosing local noon as the starting guess.
// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html

import { type Coordinate, degrees, mod, normalize, radians } from "./math";
import { dayAt } from "./tz";

export const solarEvents = [
  "solarMidnight",
  "astronomicalDawn",
  "nauticalDawn",
  "civilDawn",
  "sunrise",
  "solarNoon",
  "sunset",
  "civilDusk",
  "nauticalDusk",
  "astronomicalDusk",
] as const;
export type SolarEvent = (typeof solarEvents)[number];

/** Sun altitude (degrees, sun's center) that defines an event; null for the transits. */
export function eventAltitude(event: SolarEvent): number | null {
  switch (event) {
    case "solarMidnight":
    case "solarNoon":
      return null;
    case "astronomicalDawn":
    case "astronomicalDusk":
      return -18;
    case "nauticalDawn":
    case "nauticalDusk":
      return -12;
    case "civilDawn":
    case "civilDusk":
      return -6;
    // Standard refraction (34') plus solar semidiameter (16').
    case "sunrise":
    case "sunset":
      return -0.833;
  }
}

/** -1 before solar noon, +1 after, 0 for the transits. */
function direction(event: SolarEvent): number {
  const i = solarEvents.indexOf(event);
  return i === 0 || i === 5 ? 0 : i < 5 ? -1 : 1;
}

export const eventNames: Record<SolarEvent, string> = {
  solarMidnight: "Solar midnight",
  astronomicalDawn: "Astronomical dawn",
  nauticalDawn: "Nautical dawn",
  civilDawn: "Civil dawn",
  sunrise: "Sunrise",
  solarNoon: "Solar noon",
  sunset: "Sunset",
  civilDusk: "Civil dusk",
  nauticalDusk: "Nautical dusk",
  astronomicalDusk: "Astronomical dusk",
};

/** An instant, or why the event doesn't happen today. */
export type EventTime = number | "sunAlwaysAbove" | "sunAlwaysBelow";

export interface SunPosition {
  /** Degrees. */
  declination: number;
  /** Minutes (apparent minus mean solar time). */
  equationOfTime: number;
  /** Apparent ecliptic longitude, degrees. */
  apparentLongitude: number;
  /** Apparent right ascension, degrees. */
  rightAscension: number;
  /** Distance from Earth, AU. */
  distance: number;
  /** Apparent semidiameter, degrees. */
  semidiameter: number;
  /** Horizontal parallax, degrees. */
  parallax: number;
}

export interface SolarDay {
  coordinate: Coordinate;
  solarNoon: number;
  /** Start of this solar day. */
  solarMidnight: number;
  /** End of this solar day. */
  nextSolarMidnight: number;
  /** Every event, chronological from solar midnight. */
  events: Record<SolarEvent, EventTime>;
}

const secondsPerDegree = 240;
const iterations = 5;

export function sunPosition(instant: number): SunPosition {
  const julianDay = instant / 86_400_000 + 2_440_587.5;
  const t = (julianDay - 2_451_545) / 36_525;

  const meanLongitude = mod(280.46646 + t * (36000.76983 + 0.0003032 * t), 360);
  const meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  const eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const m = radians(meanAnomaly);
  const equationOfCenter =
    Math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(2 * m) * (0.019993 - 0.000101 * t) +
    Math.sin(3 * m) * 0.000289;
  const trueLongitude = meanLongitude + equationOfCenter;
  const omega = 125.04 - 1934.136 * t;
  const apparentLongitude = trueLongitude - 0.00569 - 0.00478 * Math.sin(radians(omega));
  const obliquitySeconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813));
  const meanObliquity = 23 + (26 + obliquitySeconds / 60) / 60;
  const obliquity = radians(meanObliquity + 0.00256 * Math.cos(radians(omega)));

  const declination = degrees(Math.asin(Math.sin(obliquity) * Math.sin(radians(apparentLongitude))));

  const y = Math.tan(obliquity / 2) ** 2;
  const l0 = radians(meanLongitude);
  const e = eccentricity;
  const eot =
    y * Math.sin(2 * l0) -
    2 * e * Math.sin(m) +
    4 * e * y * Math.sin(m) * Math.cos(2 * l0) -
    0.5 * y * y * Math.sin(4 * l0) -
    1.25 * e * e * Math.sin(2 * m);

  const lambda = radians(apparentLongitude);
  const rightAscension = mod(degrees(Math.atan2(Math.cos(obliquity) * Math.sin(lambda), Math.cos(lambda))), 360);
  const trueAnomaly = radians(meanAnomaly + equationOfCenter);
  const distance = (1.000001018 * (1 - e * e)) / (1 + e * Math.cos(trueAnomaly));
  return {
    declination,
    equationOfTime: 4 * degrees(eot),
    apparentLongitude: mod(apparentLongitude, 360),
    rightAscension,
    distance,
    semidiameter: 959.63 / 3600 / distance,
    parallax: 8.794 / 3600 / distance,
  };
}

/** Apparent (sundial) solar time at `instant`, minutes past solar midnight, in [0, 1440). */
export function apparentSolarMinutes(instant: number, longitude: number): number {
  const utcMinutes = mod(instant / 60_000, 1440);
  return mod(utcMinutes + 4 * longitude + sunPosition(instant).equationOfTime, 1440);
}

/** Solar hour angle, degrees in (-180, 180]; 0 at solar noon, increasing with time. */
export function solarHourAngle(instant: number, longitude: number): number {
  return normalize((apparentSolarMinutes(instant, longitude) - 720) / 4);
}

/** Altitude (degrees) of a body's center at an hour angle, for a declination. */
export function altitude(hourAngle: number, latitude: number, declination: number): number {
  const lat = radians(latitude), dec = radians(declination), h = radians(hourAngle);
  const s = Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(h);
  return degrees(Math.asin(Math.min(Math.max(s, -1), 1)));
}

/** The sun's altitude at `instant` from `coordinate`. */
export function sunAltitude(instant: number, coordinate: Coordinate): number {
  return altitude(solarHourAngle(instant, coordinate.longitude), coordinate.latitude, sunPosition(instant).declination);
}

/** The solar day centered on the solar noon of `instant`'s local calendar day. */
export function solarDayFor(instant: number, coordinate: Coordinate, timeZone: string): SolarDay {
  return solarDayNearestNoon(dayAt(instant, 0, 12, 0, timeZone), coordinate);
}

/** The solar day (solar midnight to solar midnight) containing `instant`. */
export function solarDayContaining(instant: number, coordinate: Coordinate): SolarDay {
  const day = solarDayNearestNoon(instant, coordinate);
  if (instant < day.solarMidnight) return solarDayNearestNoon(day.solarNoon - 86_400_000, coordinate);
  if (instant >= day.nextSolarMidnight) return solarDayNearestNoon(day.solarNoon + 86_400_000, coordinate);
  return day;
}

export function solarDayNearestNoon(guess: number, coordinate: Coordinate): SolarDay {
  const lon = coordinate.longitude;
  const noon = solve(0, guess, lon);
  const midnight = solve(180, noon - 43_200_000, lon);
  const nextMidnight = solve(180, noon + 43_200_000, lon);
  const events = {} as Record<SolarEvent, EventTime>;
  for (const event of solarEvents) {
    const alt = eventAltitude(event);
    events[event] =
      event === "solarNoon" ? noon
      : event === "solarMidnight" ? midnight
      : eventTime(alt!, direction(event), noon, coordinate);
  }
  return { coordinate, solarNoon: noon, solarMidnight: midnight, nextSolarMidnight: nextMidnight, events };
}

/**
 * When the sun's center crosses `alt` degrees on the solar day around `noon`: before
 * noon (`dir` -1, rising) or after (+1, setting). For altitudes other than the ten
 * standard events, such as the Edo calendar's dawn and dusk.
 */
export function sunCrossing(alt: number, dir: -1 | 1, noon: number, coordinate: Coordinate): EventTime {
  return eventTime(alt, dir, noon, coordinate);
}

function eventTime(alt: number, dir: number, noon: number, coordinate: Coordinate): EventTime {
  let h = altitudeHourAngle(alt, coordinate.latitude, sunPosition(noon).declination);
  if (typeof h === "string") return h;
  let t = noon + dir * h * secondsPerDegree * 1000;
  for (let i = 0; i < iterations; i++) {
    h = altitudeHourAngle(alt, coordinate.latitude, sunPosition(t).declination);
    if (typeof h === "string") return h;
    const error = normalize(dir * h - solarHourAngle(t, coordinate.longitude));
    t += error * secondsPerDegree * 1000;
  }
  return t;
}

/** Hour angle (degrees, positive) at which the sun's center reaches `alt`. */
function altitudeHourAngle(alt: number, latitude: number, declination: number): number | "sunAlwaysAbove" | "sunAlwaysBelow" {
  // Avoid dividing by cos(90 deg) exactly at the poles.
  const lat = radians(Math.min(Math.max(latitude, -89.9999), 89.9999));
  const dec = radians(declination);
  const cosH = (Math.sin(radians(alt)) - Math.sin(lat) * Math.sin(dec)) / (Math.cos(lat) * Math.cos(dec));
  if (cosH > 1) return "sunAlwaysBelow";
  if (cosH < -1) return "sunAlwaysAbove";
  return degrees(Math.acos(cosH));
}

/** The instant nearest `guess` at which the hour angle equals `target`. */
function solve(target: number, guess: number, longitude: number): number {
  let t = guess;
  for (let i = 0; i < iterations; i++) {
    t += normalize(target - solarHourAngle(t, longitude)) * secondsPerDegree * 1000;
  }
  return t;
}

export const isInstant = (time: EventTime): time is number => typeof time === "number";
