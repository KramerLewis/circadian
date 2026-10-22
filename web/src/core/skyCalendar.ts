// Notable sky days: solstices, equinoxes, full moons (with supermoons and blue moons)
// and new moons. A port of ios/SunCore SkyCalendar.

import { earthRadiusKm, moonPosition } from "./lunar";
import { mod } from "./math";
import { sunPosition } from "./solar";
import { addDays, localParts, startOfDay } from "./tz";

export type Season = "marchEquinox" | "juneSolstice" | "septemberEquinox" | "decemberSolstice";
const seasonLongitudes: Record<Season, number> = {
  marchEquinox: 0,
  juneSolstice: 90,
  septemberEquinox: 180,
  decemberSolstice: 270,
};

export type SkyKind =
  | { type: "season"; season: Season }
  | { type: "fullMoon"; supermoon: boolean; blueMoon: boolean }
  | { type: "newMoon" };

export interface SkyOccurrence {
  kind: SkyKind;
  date: number;
  /** Earth-moon distance at a full or new moon, km. */
  moonDistance?: number;
}

/** A full moon closer than this is a supermoon. */
export const supermoonDistance = 362_000;

const day = 86_400_000;

/** Every notable instant in [start, end), chronological. Blue moons are judged in `timeZone`. */
export function skyOccurrences(start: number, end: number, timeZone: string): SkyOccurrence[] {
  const found: SkyOccurrence[] = [];
  for (const season of Object.keys(seasonLongitudes) as Season[]) {
    for (const date of crossings(start, end, day, seasonLongitudes[season], sunLongitude)) {
      found.push({ kind: { type: "season", season }, date });
    }
  }
  // Look back a month so a blue moon early in the window knows its month's first full moon.
  const fullMoons = crossings(start - 32 * day, end, 6 * 3_600_000, 180, elongation);
  let previousMonth = "";
  for (const date of fullMoons) {
    const p = localParts(date, timeZone);
    const month = `${p.year}-${p.month}`;
    const blue = month === previousMonth;
    previousMonth = month;
    if (date < start) continue;
    const distance = moonDistance(date);
    found.push({ kind: { type: "fullMoon", supermoon: distance < supermoonDistance, blueMoon: blue }, date, moonDistance: distance });
  }
  for (const date of crossings(start, end, 6 * 3_600_000, 0, elongation)) {
    found.push({ kind: { type: "newMoon" }, date, moonDistance: moonDistance(date) });
  }
  return found.sort((a, b) => a.date - b.date);
}

const priority = (o: SkyOccurrence) => (o.kind.type === "season" ? 0 : o.kind.type === "fullMoon" ? 1 : 2);

/** The notable event (if any) on the local calendar day containing `instant`. */
export function skyEventOnDay(instant: number, timeZone: string): SkyOccurrence | undefined {
  const start = startOfDay(instant, timeZone);
  const end = addDays(instant, 1, timeZone);
  return skyOccurrences(start, end, timeZone).sort((a, b) => priority(a) - priority(b))[0];
}

/** The next notable event after today, if within `days` days. */
export function skyUpcoming(instant: number, days: number, timeZone: string): SkyOccurrence | undefined {
  const tomorrow = addDays(instant, 1, timeZone);
  return skyOccurrences(tomorrow, addDays(instant, 1 + days, timeZone), timeZone)[0];
}

/** "Summer solstice", "Blue supermoon", "New moon". Seasons follow the hemisphere. */
export function skyTitle(o: SkyOccurrence, southern: boolean): string {
  switch (o.kind.type) {
    case "season": {
      const s = o.kind.season;
      const summer = (s === "juneSolstice") !== southern;
      const spring = (s === "marchEquinox") !== southern;
      if (s === "juneSolstice" || s === "decemberSolstice") return summer ? "Summer solstice" : "Winter solstice";
      return spring ? "Spring equinox" : "Autumn equinox";
    }
    case "fullMoon": {
      const { supermoon, blueMoon } = o.kind;
      if (supermoon && blueMoon) return "Blue supermoon";
      if (supermoon) return "Supermoon";
      if (blueMoon) return "Blue moon";
      return "Full moon";
    }
    case "newMoon":
      return "New moon";
  }
}

const sunLongitude = (t: number) => sunPosition(t).apparentLongitude;

/** Moon's ecliptic longitude minus the sun's, [0, 360): 0 new, 180 full. */
function elongation(t: number): number {
  return mod(moonPosition(t).longitude - sunLongitude(t), 360);
}

function moonDistance(t: number): number {
  return moonPosition(t).distance * earthRadiusKm;
}

/** Instants in [start, end) where an increasing angle passes `target`. */
function crossings(start: number, end: number, stepMs: number, target: number, angle: (t: number) => number): number[] {
  const offset = (t: number) => {
    let d = (angle(t) - target) % 360;
    if (d < -180) d += 360;
    else if (d >= 180) d -= 360;
    return d;
  };
  const result: number[] = [];
  let t = start;
  let previous = offset(t);
  while (t < end) {
    const next = t + stepMs;
    const current = offset(next);
    // A small negative-to-positive step is a crossing; a wrap from +180 to -180 isn't.
    if (previous < 0 && current >= 0 && current - previous < 90) {
      let a = t, b = next;
      for (let i = 0; i < 40; i++) {
        const mid = (a + b) / 2;
        if (offset(mid) < 0) a = mid;
        else b = mid;
      }
      const crossing = (a + b) / 2;
      if (crossing >= start && crossing < end) result.push(crossing);
    }
    t = next;
    previous = current;
  }
  return result;
}
