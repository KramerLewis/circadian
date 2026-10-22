// Relative readouts ("2h 14m after sunrise") across solar-day boundaries, and text
// formatting. A port of ios/SunCore SolarTimeline, SolarReadout and SolarFormat.

import type { Coordinate } from "./math";
import { type SolarEvent, eventNames, isInstant, solarDayContaining, solarDayNearestNoon, solarEvents } from "./solar";

export interface Occurrence {
  event: SolarEvent;
  date: number;
}

/** Events from `days` solar days before to `days` after the one containing `instant`. */
export function timeline(instant: number, coordinate: Coordinate, days = 3): Occurrence[] {
  const today = solarDayContaining(instant, coordinate);
  const out: Occurrence[] = [];
  for (let offset = -days; offset <= days; offset++) {
    const day = offset === 0 ? today : solarDayNearestNoon(today.solarNoon + offset * 86_400_000, coordinate);
    for (const event of solarEvents) {
      const time = day.events[event];
      if (isInstant(time)) out.push({ event, date: time });
    }
  }
  return out.sort((a, b) => a.date - b.date);
}

export interface Relative {
  event: SolarEvent;
  date: number;
  /** Milliseconds, never negative. */
  interval: number;
}

export interface Readout {
  previousHorizon?: Relative;
  nextHorizon?: Relative;
  nextEvent?: Relative;
  polarCondition?: "midnightSun" | "polarNight";
  /** The nearest of sunrise, solar noon, sunset and solar midnight. */
  nearestAnchor?: Relative;
  nearestAnchorIsPast: boolean;
}

const anchors = new Set<SolarEvent>(["sunrise", "solarNoon", "sunset", "solarMidnight"]);
const horizon = new Set<SolarEvent>(["sunrise", "sunset"]);

export function readout(instant: number, coordinate: Coordinate): Readout {
  const line = timeline(instant, coordinate);
  const relative = (o?: Occurrence): Relative | undefined =>
    o && { event: o.event, date: o.date, interval: Math.abs(o.date - instant) };
  const previous = line.filter((o) => horizon.has(o.event) && o.date <= instant).at(-1);
  const nextHorizon = line.find((o) => horizon.has(o.event) && o.date > instant);
  const nextEvent = line.find((o) => o.date > instant);
  let anchor: Occurrence | undefined;
  for (const o of line) {
    if (anchors.has(o.event) && (!anchor || Math.abs(o.date - instant) < Math.abs(anchor.date - instant))) anchor = o;
  }
  const sunrise = solarDayContaining(instant, coordinate).events.sunrise;
  return {
    previousHorizon: relative(previous),
    nextHorizon: relative(nextHorizon),
    nextEvent: relative(nextEvent),
    nearestAnchor: relative(anchor),
    nearestAnchorIsPast: anchor ? anchor.date <= instant : false,
    polarCondition: sunrise === "sunAlwaysAbove" ? "midnightSun" : sunrise === "sunAlwaysBelow" ? "polarNight" : undefined,
  };
}

/** "2h 14m", "14m", or "<1m". Rounds down to the minute. */
export function duration(ms: number): string {
  const minutes = Math.floor(Math.max(ms, 0) / 60_000);
  if (minutes < 1) return "<1m";
  const hours = Math.floor(minutes / 60);
  return hours === 0 ? `${minutes}m` : `${hours}h ${minutes % 60}m`;
}

/** "2h 14m after sunrise" or "4h 51m until sunset". */
export function relativeText(r: Relative, isPast: boolean): string {
  return `${duration(r.interval)} ${isPast ? "after" : "until"} ${eventNames[r.event].toLowerCase()}`;
}

/** 24-hour apparent solar time, e.g. "11:42". */
export function solarClock(minutes: number): string {
  const total = Math.floor(minutes) % 1440;
  const h = Math.floor(total / 60), m = total % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}
