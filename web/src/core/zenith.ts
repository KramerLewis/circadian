// Zenith passage: the day the sun passes straight overhead at solar noon, so upright
// things cast (almost) no shadow. It happens twice a year anywhere between the tropics,
// when the sun's declination at noon equals the latitude; the Maya, among others, built
// to mark it. Outside the tropics the sun is never overhead. A port of ios/SunCore
// ZenithPassage.

import type { Coordinate } from "./math";
import { solarDayNearestNoon, sunPosition } from "./solar";

const day = 86_400_000;

export interface ZenithPassage {
  /** Solar noon on the passage day. */
  date: number;
  /** The sun's altitude then, degrees (90 is straight overhead). */
  altitude: number;
}

/** The sun reaches at most this declination (the tropics' latitude). */
const tropic = 23.44;

/** Zenith passages with their noon in [start, end), chronological. */
export function zenithPassages(start: number, end: number, coordinate: Coordinate): ZenithPassage[] {
  const lat = coordinate.latitude;
  if (Math.abs(lat) > tropic + 0.01) return [];
  const offset = (t: number) => sunPosition(t).declination - lat;
  const found: ZenithPassage[] = [];
  // Solar noon moves by under a minute a day, so stepping a day at a time stays on noon
  // well enough to compare declinations; the passage's own noon is solved exactly.
  let a = solarDayNearestNoon(start - day, coordinate).solarNoon;
  let fa = offset(a);
  while (a < end + day) {
    const b = a + day, fb = offset(b);
    if (fa < 0 !== fb < 0) {
      const noon = solarDayNearestNoon(Math.abs(fa) <= Math.abs(fb) ? a : b, coordinate).solarNoon;
      if (noon >= start && noon < end) found.push({ date: noon, altitude: 90 - Math.abs(offset(noon)) });
    }
    a = b;
    fa = fb;
  }
  return found;
}

/** The first passage after `date` (within a year and a bit). */
export function nextZenithPassage(date: number, coordinate: Coordinate): ZenithPassage | undefined {
  return zenithPassages(date + day / 2, date + 370 * day, coordinate)[0];
}
