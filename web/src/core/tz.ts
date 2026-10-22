// Calendar arithmetic in an IANA time zone, using only Intl. Instants are milliseconds
// since 1970 throughout the core.

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formatters.set(timeZone, f);
  }
  return f;
}

export interface LocalParts {
  year: number;
  /** 1-12 */
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

/** The wall-clock reading of `instant` in `timeZone`. */
export function localParts(instant: number, timeZone: string): LocalParts {
  const parts: Record<string, number> = {};
  for (const p of formatter(timeZone).formatToParts(new Date(instant))) {
    if (p.type !== "literal") parts[p.type] = Number(p.value);
  }
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour % 24,
    minute: parts.minute,
    second: parts.second,
  };
}

/** Milliseconds `timeZone` is ahead of UTC at `instant`. */
export function offsetMs(instant: number, timeZone: string): number {
  const p = localParts(instant, timeZone);
  const asUTC = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUTC - Math.floor(instant / 1000) * 1000;
}

/** The instant a wall-clock time happens in `timeZone` (the earlier one in a DST overlap). */
export function zonedInstant(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  timeZone: string,
): number {
  const wall = Date.UTC(year, month - 1, day, hour, minute);
  let t = wall - offsetMs(wall, timeZone);
  t = wall - offsetMs(t, timeZone);
  return t;
}

/** Local midnight starting the day that contains `instant`. */
export function startOfDay(instant: number, timeZone: string): number {
  const p = localParts(instant, timeZone);
  return zonedInstant(p.year, p.month, p.day, 0, 0, timeZone);
}

/** The same wall-clock day `days` later, at `hour`:`minute`. */
export function dayAt(instant: number, days: number, hour: number, minute: number, timeZone: string): number {
  const p = localParts(instant, timeZone);
  const d = new Date(Date.UTC(p.year, p.month - 1, p.day + days));
  return zonedInstant(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), hour, minute, timeZone);
}

/** Local midnight `days` after the day containing `instant`. */
export function addDays(instant: number, days: number, timeZone: string): number {
  return dayAt(instant, days, 0, 0, timeZone);
}

/** Whole calendar days from the day of `a` to the day of `b`. */
export function daysBetween(a: number, b: number, timeZone: string): number {
  const pa = localParts(a, timeZone), pb = localParts(b, timeZone);
  return Math.round((Date.UTC(pb.year, pb.month - 1, pb.day) - Date.UTC(pa.year, pa.month - 1, pa.day)) / 86_400_000);
}

export function browserTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}
