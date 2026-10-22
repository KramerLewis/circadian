// Clock and date text in a given time zone.

const cache = new Map<string, Intl.DateTimeFormat>();

function get(key: string, make: () => Intl.DateTimeFormat): Intl.DateTimeFormat {
  let f = cache.get(key);
  if (!f) {
    f = make();
    cache.set(key, f);
  }
  return f;
}

export type ClockStyle = "locale" | "twelveHour" | "twentyFourHour";

/** "7:42 AM" (locale default), or forced 12- or 24-hour. */
export function clockTime(instant: number, timeZone: string, style: ClockStyle = "locale"): string {
  const f = get(`t|${timeZone}|${style}`, () =>
    new Intl.DateTimeFormat(undefined, {
      timeZone,
      hour: style === "twentyFourHour" ? "2-digit" : "numeric",
      minute: "2-digit",
      ...(style === "locale" ? {} : { hourCycle: style === "twelveHour" ? "h12" : "h23" }),
    }),
  );
  return f.format(instant);
}

/** "Mar 3, 2026" */
export function shortDate(instant: number, timeZone: string): string {
  return get(`d|${timeZone}`, () => new Intl.DateTimeFormat(undefined, { timeZone, month: "short", day: "numeric", year: "numeric" })).format(instant);
}

/** "Tuesday, March 3" */
export function longDate(instant: number, timeZone: string): string {
  return get(`l|${timeZone}`, () => new Intl.DateTimeFormat(undefined, { timeZone, weekday: "long", month: "long", day: "numeric" })).format(instant);
}
