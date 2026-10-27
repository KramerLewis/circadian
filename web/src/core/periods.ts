// Two ways of naming where you are in the day, both stretching with the seasons:
//
// Sun periods (this app's own scale): the four milestones of the solar day, sunrise (R),
// solar noon (N), sunset (S) and solar midnight (M), split the day into quarters; each
// quarter splits into thirds. The third after a milestone is X+, the one before is -X,
// and the middle third is a number (0 mid-morning, 1 mid-afternoon, 2 mid-evening,
// 3 deep night). Each milestone itself gets a short window (X) of ±15 minutes, so the
// moment is something you can catch:
//
//   … -R  R  R+  0  -N  N  N+  1  -S  S  S+  2  -M  M  M+  3  -R …
//
// The same scale works for the moon, in lowercase, with moonrise (r), the moon highest
// (n), moonset (s) and the moon lowest (m).
//
// Wadokei (Edo-period Japanese temporal hours): daylight from dawn to dusk, and night
// from dusk to dawn, each split into six equal hours named for the zodiac animals.
// Dawn and dusk are when the sun is 7°21'40" below the horizon (the Kansei calendar's
// definition), roughly half an hour beyond sunrise and sunset.

import { lunarEvents } from "./lunar";
import type { Coordinate } from "./math";
import { timeline } from "./readout";
import { type EventTime, isInstant, solarDayContaining, solarDayNearestNoon, sunCrossing } from "./solar";

const minute = 60_000;
/** Half of a milestone's window. */
export const milestoneGrace = 15 * minute;

export interface Anchor {
  /** "R", "N", "S", "M" (or lowercase for the moon). */
  letter: string;
  date: number;
}

export interface Period {
  /** "-R", "R", "R+", "0", … */
  code: string;
  start: number;
  end: number;
  /** The quarter of the day it's in: from one milestone to the next. */
  from: Anchor;
  to: Anchor;
  /** How far through that quarter, 0…1. */
  fraction: number;
}

/**
 * The period containing `now`, given milestones in time order (they repeat R N S M or,
 * in polar days, just N M). `middle` names the middle third after each milestone letter.
 */
export function periodAt(now: number, anchors: Anchor[], middle: Record<string, string>): Period | undefined {
  const i = anchors.findIndex((a, k) => a.date <= now && (anchors[k + 1]?.date ?? -Infinity) > now);
  if (i < 0) return undefined;
  const from = anchors[i], to = anchors[i + 1];
  const quarter = to.date - from.date;
  const third = quarter / 3;
  // The window shrinks on very short quarters, so it never swallows a section.
  const grace = Math.min(milestoneGrace, third / 3);
  const fraction = (now - from.date) / quarter;
  const base = { from, to, fraction };
  const prevGrace = graceAround(anchors, i), nextGrace = graceAround(anchors, i + 1);
  if (now < from.date + prevGrace) return { code: from.letter, start: from.date - prevGrace, end: from.date + prevGrace, ...base };
  if (now >= to.date - nextGrace) return { code: to.letter, start: to.date - nextGrace, end: to.date + nextGrace, ...base };
  if (now < from.date + third) return { code: `${from.letter}+`, start: from.date + grace, end: from.date + third, ...base };
  if (now < from.date + 2 * third) return { code: middle[from.letter] ?? "·", start: from.date + third, end: from.date + 2 * third, ...base };
  return { code: `-${to.letter}`, start: from.date + 2 * third, end: to.date - nextGrace, ...base };
}

/** A milestone's half-window: 15 minutes, or less if a neighboring quarter is short. */
function graceAround(anchors: Anchor[], k: number): number {
  const before = k > 0 ? anchors[k].date - anchors[k - 1].date : Infinity;
  const after = k + 1 < anchors.length ? anchors[k + 1].date - anchors[k].date : Infinity;
  return Math.min(milestoneGrace, before / 9, after / 9);
}

const solarLetters: Record<string, string> = { sunrise: "R", solarNoon: "N", sunset: "S", solarMidnight: "M" };
const solarMiddles: Record<string, string> = { R: "0", N: "1", S: "2", M: "3" };
/** Polar days have only noon and midnight: the half after midnight is 0, after noon 2. */
const polarMiddles: Record<string, string> = { M: "0", N: "2" };

export function solarAnchors(now: number, coordinate: Coordinate): Anchor[] {
  return timeline(now, coordinate, 2)
    .filter((o) => o.event in solarLetters)
    .map((o) => ({ letter: solarLetters[o.event], date: o.date }));
}

export function sunPeriod(now: number, coordinate: Coordinate): Period | undefined {
  const anchors = solarAnchors(now, coordinate);
  const polar = !anchors.some((a) => a.letter === "R");
  return periodAt(now, anchors, polar ? polarMiddles : solarMiddles);
}

const lunarLetters: Record<string, string> = { moonrise: "r", moonTransit: "n", moonset: "s", moonLowerTransit: "m" };

export function moonPeriod(now: number, coordinate: Coordinate): Period | undefined {
  const anchors = lunarEvents(now - 40 * 3_600_000, now + 40 * 3_600_000, coordinate).map((e) => ({
    letter: lunarLetters[e.event],
    date: e.date,
  }));
  const polar = !anchors.some((a) => a.letter === "r");
  return periodAt(now, anchors, polar ? { m: "0", n: "2" } : { r: "0", n: "1", s: "2", m: "3" });
}

// MARK: Wadokei

export interface Toki {
  /** The zodiac animal's kanji, e.g. 午. */
  kanji: string;
  /** "Horse" */
  animal: string;
  /** The bell count the hour was called by (九つ at noon and midnight, then down to 四つ). */
  count: number;
  start: number;
  end: number;
}

/** In order from dusk: 酉 (暮れ六つ) through to 申. */
const night = [
  { kanji: "酉", animal: "Rooster", count: 6 },
  { kanji: "戌", animal: "Dog", count: 5 },
  { kanji: "亥", animal: "Boar", count: 4 },
  { kanji: "子", animal: "Rat", count: 9 },
  { kanji: "丑", animal: "Ox", count: 8 },
  { kanji: "寅", animal: "Tiger", count: 7 },
];
const day = [
  { kanji: "卯", animal: "Rabbit", count: 6 },
  { kanji: "辰", animal: "Dragon", count: 5 },
  { kanji: "巳", animal: "Snake", count: 4 },
  { kanji: "午", animal: "Horse", count: 9 },
  { kanji: "未", animal: "Goat", count: 8 },
  { kanji: "申", animal: "Monkey", count: 7 },
];

export const wadokeiTwilight = -(7 + 21 / 60 + 40 / 3600);

/**
 * The twelve temporal hours of the solar day containing `now` (plus the hours either
 * side of it), from the dusk before to the dusk after. Without a dawn or dusk (polar
 * days and nights), the hours fall back to equal two-hour steps with 子 starting at solar
 * midnight, as the fixed-hour clocks did.
 */
export function wadokeiHours(now: number, coordinate: Coordinate): Toki[] {
  const today = solarDayContaining(now, coordinate);
  const days = [-1, 0, 1].map((k) => (k === 0 ? today : solarDayNearestNoon(today.solarNoon + k * 86_400_000, coordinate)));
  const twilights: { dawn: EventTime; dusk: EventTime; day: typeof today }[] = days.map((d) => ({
    dawn: sunCrossing(wadokeiTwilight, -1, d.solarNoon, coordinate),
    dusk: sunCrossing(wadokeiTwilight, 1, d.solarNoon, coordinate),
    day: d,
  }));
  const hours: Toki[] = [];
  const split = (start: number, end: number, names: typeof day) =>
    names.forEach((n, k) => hours.push({ ...n, start: start + ((end - start) * k) / 6, end: start + ((end - start) * (k + 1)) / 6 }));
  if (twilights.every((t) => isInstant(t.dawn) && isInstant(t.dusk))) {
    for (let k = 0; k < 3; k++) {
      const t = twilights[k];
      if (k > 0) split(twilights[k - 1].dusk as number, t.dawn as number, night);
      split(t.dawn as number, t.dusk as number, day);
    }
  } else {
    // Equal hours: 子 from solar midnight, 午 from solar noon.
    for (const d of days) {
      const order = [...night.slice(3), ...day, ...night.slice(0, 3)]; // 子 … 亥
      const step = (d.nextSolarMidnight - d.solarMidnight) / 12;
      order.forEach((n, k) => hours.push({ ...n, start: d.solarMidnight + step * k, end: d.solarMidnight + step * (k + 1) }));
    }
  }
  return hours;
}

export function tokiAt(now: number, coordinate: Coordinate): Toki | undefined {
  return wadokeiHours(now, coordinate).find((h) => h.start <= now && now < h.end);
}

// MARK: Roman hours
//
// The Roman day (like the Babylonian, Greek and medieval European ones) ran from sunrise
// to sunset in twelve equal hours, so an hour stretched to about 80 minutes in summer and
// shrank to 40 in winter; hora sexta ended at midday. The night was kept in four watches
// (vigiliae) from sunset to sunrise, each three night hours long.

export interface RomanHour {
  kind: "hora" | "vigilia";
  /** 1…12 for hours of the day, 1…4 for watches of the night. */
  number: number;
  start: number;
  end: number;
}

/**
 * The Roman hours and watches around `now` (the solar days either side of it too).
 * Without a sunrise or sunset (polar days and nights), the day falls back to the
 * equinox's: six equal hours either side of solar noon.
 */
export function romanHours(now: number, coordinate: Coordinate): RomanHour[] {
  const today = solarDayContaining(now, coordinate);
  const days = [-1, 0, 1].map((k) => (k === 0 ? today : solarDayNearestNoon(today.solarNoon + k * 86_400_000, coordinate)));
  const horizon = days.map((d) => ({ rise: d.events.sunrise, set: d.events.sunset, noon: d.solarNoon }));
  const real = horizon.every((h) => isInstant(h.rise) && isInstant(h.set));
  const bounds = horizon.map((h) =>
    real ? { rise: h.rise as number, set: h.set as number } : { rise: h.noon - 6 * 3_600_000, set: h.noon + 6 * 3_600_000 },
  );
  const hours: RomanHour[] = [];
  const split = (kind: RomanHour["kind"], start: number, end: number, count: number) => {
    for (let k = 0; k < count; k++) {
      hours.push({ kind, number: k + 1, start: start + ((end - start) * k) / count, end: start + ((end - start) * (k + 1)) / count });
    }
  };
  bounds.forEach((b, k) => {
    if (k > 0) split("vigilia", bounds[k - 1].set, b.rise, 4);
    split("hora", b.rise, b.set, 12);
  });
  return hours;
}

export function romanAt(now: number, coordinate: Coordinate): RomanHour | undefined {
  return romanHours(now, coordinate).find((h) => h.start <= now && now < h.end);
}

/** Which of the twelve night hours `now` falls in, during a watch. */
export function romanNightHour(watch: RomanHour, now: number): number {
  return Math.min(12, (watch.number - 1) * 3 + Math.floor(((now - watch.start) / (watch.end - watch.start)) * 3) + 1);
}

export function romanNumeral(n: number): string {
  return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"][n] ?? String(n);
}
