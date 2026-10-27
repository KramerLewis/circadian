import { describe, expect, test } from "vitest";
import { type Anchor, milestoneGrace, moonPeriod, periodAt, romanAt, romanHours, romanNightHour, sunPeriod, tokiAt, wadokeiHours } from "../src/core/periods";
import { solarDayContaining } from "../src/core/solar";
import { instant } from "./fixtures";

const seattle = { latitude: 47.61, longitude: -122.33 };
const middles = { R: "0", N: "1", S: "2", M: "3" };

describe("sun periods", () => {
  // A 12-hour day: sunrise 6:00, noon 12:00, sunset 18:00, midnight 24:00 (all equal quarters).
  const h = 3_600_000;
  const anchors: Anchor[] = [
    { letter: "M", date: 0 }, { letter: "R", date: 6 * h }, { letter: "N", date: 12 * h },
    { letter: "S", date: 18 * h }, { letter: "M", date: 24 * h }, { letter: "R", date: 30 * h },
  ];
  const at = (hours: number) => periodAt(hours * h, anchors, middles)?.code;

  test("the sixteen sections, in order", () => {
    expect([5.9, 6, 6.3, 7, 9, 11, 11.9, 12.1, 13, 15, 17, 18, 19, 21, 23, 24.1, 25, 27, 29.9]
      .map(at)).toEqual(["R", "R", "R+", "R+", "0", "-N", "N", "N", "N+", "1", "-S", "S", "S+", "2", "-M", "M", "M+", "3", "R"]);
  });

  test("milestone windows are ±15 minutes", () => {
    const p = periodAt(12 * h, anchors, middles)!;
    expect(p.code).toBe("N");
    expect(p.end - p.start).toBe(2 * milestoneGrace);
    expect(periodAt(12 * h - milestoneGrace - 1, anchors, middles)!.code).toBe("-N");
  });

  test("Seattle on the June solstice", () => {
    expect(sunPeriod(instant("2026-06-21T15:00:00-07:00"), seattle)?.code).toBe("N+");
    expect(sunPeriod(instant("2026-06-21T21:10:00-07:00"), seattle)?.code).toBe("S");
    // Night is short in June (4 hours from solar midnight to sunrise), so its thirds are
    // 80 minutes: 60 minutes after midnight is still M+, 90 minutes is already 3.
    const day = solarDayContaining(instant("2026-06-21T12:00:00-07:00"), seattle);
    expect(sunPeriod(day.solarMidnight + 60 * 60_000, seattle)!.code).toBe("M+");
    const deep = sunPeriod(day.solarMidnight + 90 * 60_000, seattle)!;
    expect(deep.code).toBe("3");
    expect(Math.round((deep.end - deep.start) / 60_000)).toBe(80);
  });

  test("polar days fall back to noon and midnight", () => {
    const tromso = { latitude: 69.65, longitude: 18.96 };
    const p = sunPeriod(instant("2026-06-21T23:30:00+02:00"), tromso)!;
    expect(["-M", "M", "M+", "2"]).toContain(p.code);
  });

  test("the moon's scale uses lowercase letters", () => {
    expect(moonPeriod(instant("2026-11-24T22:00:00-08:00"), seattle)?.code).toMatch(/^-?[rnsm0-3]\+?$/);
  });
});

describe("wadokei", () => {
  test("six hours from dawn to dusk, 午 from midday, 子 from the middle of the night", () => {
    const hours = wadokeiHours(instant("2026-06-21T12:00:00-07:00"), seattle);
    const dayHours = hours.filter((t) => "卯辰巳午未申".includes(t.kanji));
    expect(dayHours.length % 6).toBe(0);
    expect(tokiAt(instant("2026-06-21T13:20:00-07:00"), seattle)?.kanji).toBe("午");
    expect(tokiAt(instant("2026-06-21T01:20:00-07:00"), seattle)?.kanji).toBe("子");
    // Summer day hours are long, night hours short.
    const horse = hours.find((t) => t.kanji === "午")!;
    const rat = hours.find((t) => t.kanji === "子")!;
    expect((horse.end - horse.start) / 60_000).toBeGreaterThan(150);
    expect((rat.end - rat.start) / 60_000).toBeLessThan(80);
  });
});

describe("roman hours", () => {
  test("twelve hours from sunrise to sunset, hora VI ending at midday", () => {
    const noon = instant("2026-06-21T12:00:00-07:00");
    const day = solarDayContaining(noon, seattle);
    const hours = romanHours(noon, seattle).filter((h) => h.kind === "hora" && h.start >= day.solarMidnight && h.end <= day.nextSolarMidnight);
    expect(hours.map((h) => h.number)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    expect(hours[0].start).toBe(day.events.sunrise);
    expect(hours[11].end).toBe(day.events.sunset);
    // Sixteen hours of daylight in June: each hour is 80 minutes.
    expect(Math.round((hours[0].end - hours[0].start) / 60_000)).toBe(80);
    expect(Math.abs(hours[5].end - day.solarNoon) / 60_000).toBeLessThan(3);
    expect(romanAt(instant("2026-06-21T15:00:00-07:00"), seattle)).toMatchObject({ kind: "hora", number: 8 });
  });

  test("four watches from sunset to sunrise", () => {
    const night = instant("2026-12-21T23:30:00-08:00");
    const watch = romanAt(night, seattle)!;
    expect(watch.kind).toBe("vigilia");
    expect(watch.number).toBe(2);
    // A 16-hour December night: watches of 4 hours.
    expect(Math.round((watch.end - watch.start) / 3_600_000)).toBe(4);
    expect(romanNightHour(watch, night)).toBeGreaterThanOrEqual(4);
    expect(romanNightHour(watch, night)).toBeLessThanOrEqual(6);
  });

  test("polar days fall back to equal hours around noon", () => {
    const tromso = { latitude: 69.65, longitude: 18.96 };
    const h = romanAt(instant("2026-06-21T12:00:00+02:00"), tromso)!;
    expect(h.kind).toBe("hora");
    expect(Math.round((h.end - h.start) / 60_000)).toBe(60);
  });
});
