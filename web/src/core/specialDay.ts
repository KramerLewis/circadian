// The banner for a special sky day, and the eclipses visible from a place. A port of
// ios/Shared/SpecialDayText.swift.

import { type LunarEclipse, type SolarEclipse, lunarEclipses, solarEclipses } from "./eclipse";
import { clockTime } from "./format";
import { lunarEvents, moonAltitude } from "./lunar";
import type { Coordinate } from "./math";
import { duration } from "./readout";
import { type SkyOccurrence, skyEventOnDay, skyTitle, skyUpcoming } from "./skyCalendar";
import { isInstant, solarDayFor, sunAltitude } from "./solar";
import { addDays, daysBetween, startOfDay } from "./tz";

export type SpecialStyle =
  | "solstice" | "equinox" | "fullMoon" | "supermoon" | "blueMoon" | "newMoon" | "lunarEclipse" | "solarEclipse";

export interface SpecialDay {
  style: SpecialStyle;
  title: string;
  lines: string[];
  /** For compact places: "Supermoon tonight". */
  short: string;
}

export type VisibleEclipse = { type: "lunar"; eclipse: LunarEclipse } | { type: "solar"; eclipse: SolarEclipse };

export const eclipseDate = (e: VisibleEclipse): number => (e.type === "lunar" ? e.eclipse.greatest : e.eclipse.maximum);

export function fromOccurrence(o: SkyOccurrence, coordinate: Coordinate, date: number, timeZone: string): SpecialDay {
  const title = skyTitle(o, coordinate.latitude < 0);
  switch (o.kind.type) {
    case "season": {
      const day = solarDayFor(date, coordinate, timeZone);
      const rise = day.events.sunrise, set = day.events.sunset;
      const length = isInstant(rise) && isInstant(set) ? duration(set - rise) : undefined;
      if (o.kind.season === "juneSolstice" || o.kind.season === "decemberSolstice") {
        const longest = title.startsWith("Summer");
        return {
          style: "solstice",
          title,
          lines: [
            length ? `${length} of daylight, the ${longest ? "most" : "least"} all year.` : longest ? "The longest day of the year." : "The shortest day of the year.",
            `Days start getting ${longest ? "shorter" : "longer"} tomorrow.`,
          ],
          short: title,
        };
      }
      return {
        style: "equinox",
        title,
        lines: [`Day and night are nearly equal${length ? `: ${length} of daylight.` : "."}`, "The sun rises due east and sets due west."],
        short: title,
      };
    }
    case "fullMoon": {
      const { supermoon, blueMoon } = o.kind;
      const facts: string[] = [];
      if (supermoon && o.moonDistance) {
        facts.push(`Full moon closest to Earth: ${Math.round(o.moonDistance).toLocaleString()} km.`);
        facts.push("About 7% bigger and 15% brighter than usual.");
      }
      if (blueMoon) facts.push("The second full moon this month.");
      const start = startOfDay(date, timeZone);
      const rise = lunarEvents(start, addDays(date, 1, timeZone), coordinate).find((e) => e.event === "moonrise");
      if (rise) facts.push(`Moonrise at ${clockTime(rise.date, timeZone)}.`);
      return { style: supermoon ? "supermoon" : blueMoon ? "blueMoon" : "fullMoon", title, lines: facts.slice(0, 2), short: `${title} tonight` };
    }
    case "newMoon":
      return { style: "newMoon", title, lines: ["The darkest skies of the month:", "good for stargazing tonight."], short: "New moon: dark skies" };
  }
}

export function fromEclipse(v: VisibleEclipse, coordinate: Coordinate, timeZone: string): SpecialDay {
  const time = (t?: number) => (t === undefined ? "?" : clockTime(t, timeZone));
  if (v.type === "lunar") {
    const e = v.eclipse;
    const up = (t?: number) => t !== undefined && moonAltitude(t, coordinate) > 0;
    switch (e.kind) {
      case "total":
        return {
          style: "lunarEclipse",
          title: "Total lunar eclipse",
          lines: [
            `A blood moon: totality ${time(e.totalStart)}–${time(e.totalEnd)}.`,
            up(e.totalStart) && up(e.totalEnd) ? "The moon is up for all of totality." : "Part of totality happens with the moon below the horizon.",
          ],
          short: "Blood moon tonight",
        };
      case "partial":
        return {
          style: "lunarEclipse",
          title: "Partial lunar eclipse",
          lines: [
            `${Math.round(e.umbralMagnitude * 100)}% of the moon in Earth's shadow at ${time(e.greatest)}.`,
            `Partial phase ${time(e.partialStart)}–${time(e.partialEnd)}.`,
          ],
          short: "Lunar eclipse tonight",
        };
      case "penumbral":
        return {
          style: "lunarEclipse",
          title: "Penumbral lunar eclipse",
          lines: [`A subtle dimming of the moon, deepest at ${time(e.greatest)}.`, "Easiest to see in photos."],
          short: "Lunar eclipse tonight",
        };
    }
  }
  const e = v.eclipse;
  const window = `${time(e.start)}–${time(e.end)}`;
  const lines =
    e.kind === "total" ? [`Totality here ${time(e.centralStart)}–${time(e.centralEnd)}.`, `Eclipse ${window}. Use eclipse glasses except during totality.`]
    : e.kind === "annular" ? [`A ring of fire ${time(e.centralStart)}–${time(e.centralEnd)}.`, `Eclipse ${window}. Always use eclipse glasses.`]
    : [`${Math.round(e.obscuration * 100)}% of the sun covered at ${time(e.maximum)}.`, `Eclipse ${window}. Always use eclipse glasses.`];
  const title = e.kind === "total" ? "Total solar eclipse" : e.kind === "annular" ? "Annular solar eclipse" : "Partial solar eclipse";
  return { style: "solarEclipse", title, lines, short: "Solar eclipse today" };
}

/** Today's special day at a place. An eclipse visible here outranks everything else. */
export function specialToday(coordinate: Coordinate, date: number, timeZone: string): SpecialDay | undefined {
  const eclipse = eclipseOnDay(date, coordinate, timeZone);
  if (eclipse) return fromEclipse(eclipse, coordinate, timeZone);
  const o = skyEventOnDay(date, timeZone);
  return o && fromOccurrence(o, coordinate, date, timeZone);
}

/** "Full moon in 2 days", for the next special day within three days. */
export function headsUp(coordinate: Coordinate, date: number, timeZone: string): string | undefined {
  const when = (day: number) => {
    const days = daysBetween(date, day, timeZone);
    return days <= 1 ? "tomorrow" : `in ${days} days`;
  };
  for (let offset = 1; offset <= 3; offset++) {
    const day = addDays(date, offset, timeZone) + 12 * 3_600_000;
    const eclipse = eclipseOnDay(day, coordinate, timeZone);
    if (eclipse) return `${fromEclipse(eclipse, coordinate, timeZone).title} ${when(day)}`;
  }
  const next = skyUpcoming(date, 3, timeZone);
  return next && `${skyTitle(next, coordinate.latitude < 0)} ${when(next.date)}`;
}

// MARK: Visible eclipses

const dayCache = new Map<string, VisibleEclipse | null>();
const nextCache = new Map<string, VisibleEclipse | null>();
const placeKey = (c: Coordinate) => `${Math.round(c.latitude * 10)},${Math.round(c.longitude * 10)}`;

/** The eclipse visible on the local day containing `date`, if any. */
export function eclipseOnDay(date: number, coordinate: Coordinate, timeZone: string): VisibleEclipse | undefined {
  const start = startOfDay(date, timeZone);
  const key = `${start}|${placeKey(coordinate)}`;
  if (!dayCache.has(key)) {
    if (dayCache.size > 32) dayCache.clear();
    dayCache.set(key, visibleEclipses(start, addDays(date, 1, timeZone), coordinate)[0] ?? null);
  }
  return dayCache.get(key) ?? undefined;
}

/** The next visible eclipse after `date`, looking up to `days` ahead. */
export function nextEclipse(date: number, coordinate: Coordinate, timeZone: string, days = 400): VisibleEclipse | undefined {
  const key = `${startOfDay(date, timeZone)}|${placeKey(coordinate)}`;
  if (!nextCache.has(key)) {
    if (nextCache.size > 8) nextCache.clear();
    nextCache.set(key, visibleEclipses(date, date + days * 86_400_000, coordinate).find((e) => eclipseDate(e) > date) ?? null);
  }
  return nextCache.get(key) ?? undefined;
}

function visibleEclipses(start: number, end: number, coordinate: Coordinate): VisibleEclipse[] {
  const pad = 43_200_000;
  const lunar: VisibleEclipse[] = lunarEclipses(start - pad, end + pad)
    .filter((e) => e.greatest >= start && e.greatest < end)
    // Visible if the moon is up at any point of the eclipse.
    .filter((e) =>
      [e.penumbralStart, e.partialStart, e.totalStart, e.greatest, e.totalEnd, e.partialEnd, e.penumbralEnd]
        .filter((t): t is number => t !== undefined)
        .some((t) => moonAltitude(t, coordinate) > 0),
    )
    .map((eclipse) => ({ type: "lunar", eclipse }));
  const solar: VisibleEclipse[] = solarEclipses(start - pad, end + pad, coordinate)
    .filter((e) => e.maximum >= start && e.maximum < end)
    .filter((e) => [e.start, e.maximum, e.end].some((t) => sunAltitude(t, coordinate) > -0.833))
    .map((eclipse) => ({ type: "solar", eclipse }));
  return [...lunar, ...solar].sort((a, b) => eclipseDate(a) - eclipseDate(b));
}
