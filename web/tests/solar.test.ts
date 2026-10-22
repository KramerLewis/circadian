import { describe, expect, test } from "vitest";
import { duration, readout, solarClock } from "../src/core/readout";
import { apparentSolarMinutes, solarDayContaining, solarDayFor, solarEvents } from "../src/core/solar";
import { zonedInstant } from "../src/core/tz";
import { fixture, instant } from "./fixtures";

interface SolarFixture {
  toleranceSeconds: number;
  cases: { name: string; latitude: number; longitude: number; timeZone: string; date: string; events: Record<string, string> }[];
}

const reference = fixture<SolarFixture>("solar-reference.json");
const seattle = { latitude: 47.61, longitude: -122.33 };

describe("solar calculator matches shared/fixtures/solar-reference.json", () => {
  test.each(reference.cases)("$name", (c) => {
    const [y, m, d] = c.date.split("-").map(Number);
    const day = solarDayFor(zonedInstant(y, m, d, 0, 0, c.timeZone), c, c.timeZone);
    for (const event of solarEvents) {
      const expected = c.events[event];
      const actual = day.events[event];
      if (expected === "sunAlwaysAbove" || expected === "sunAlwaysBelow") {
        expect(actual, event).toBe(expected);
      } else {
        expect(typeof actual, event).toBe("number");
        expect(Math.abs((actual as number) - instant(expected)) / 1000, event).toBeLessThanOrEqual(reference.toleranceSeconds);
      }
    }
  });
});

describe("solar days and readouts", () => {
  test("the solar day containing an instant", () => {
    const early = instant("2026-06-21T00:30:00-07:00");
    const day = solarDayContaining(early, seattle);
    expect(day.solarMidnight).toBeLessThanOrEqual(early);
    expect(day.nextSolarMidnight).toBeGreaterThan(early);
  });

  test("apparent solar time is noon at solar noon", () => {
    const noon = solarDayContaining(instant("2026-06-21T15:00:00-07:00"), seattle).solarNoon;
    expect(Math.abs(apparentSolarMinutes(noon, seattle.longitude) - 720)).toBeLessThan(0.1);
  });

  test("the poles", () => {
    const june = instant("2026-06-21T12:00:00Z");
    expect(solarDayFor(june, { latitude: 90, longitude: 0 }, "UTC").events.sunrise).toBe("sunAlwaysAbove");
    expect(solarDayFor(june, { latitude: -90, longitude: 0 }, "UTC").events.sunrise).toBe("sunAlwaysBelow");
  });

  test("readout around a June afternoon in Seattle", () => {
    const r = readout(instant("2026-06-21T15:00:00-07:00"), seattle);
    expect(r.previousHorizon?.event).toBe("sunrise");
    expect(r.nextHorizon?.event).toBe("sunset");
    expect(r.nearestAnchor?.event).toBe("solarNoon");
    expect(r.nearestAnchorIsPast).toBe(true);
    expect(r.polarCondition).toBeUndefined();
    const tromso = readout(instant("2026-06-21T23:30:00+02:00"), { latitude: 69.65, longitude: 18.96 });
    expect(tromso.polarCondition).toBe("midnightSun");
  });

  test("formatting", () => {
    expect(duration(30_000)).toBe("<1m");
    expect(duration(14 * 60_000 + 59_000)).toBe("14m");
    expect(duration((2 * 60 + 14) * 60_000)).toBe("2h 14m");
    expect(solarClock(5.5)).toBe("00:05");
    expect(solarClock(13 * 60 + 2)).toBe("13:02");
  });
});
