import { describe, expect, test } from "vitest";
import { moonDialModel, moonRingColor, dialAltitude } from "../src/core/dial";
import { lunarEvents, moonAltitude, moonPhase, phaseName } from "../src/core/lunar";
import { addDays, dayAt, zonedInstant } from "../src/core/tz";
import { fixture, instant } from "./fixtures";

interface LunarFixture {
  toleranceSeconds: number;
  illuminationTolerance: number;
  cases: {
    name: string; latitude: number; longitude: number; timeZone: string; date: string;
    events: { event: string; time: string }[]; illuminationAtNoon: number; waxingAtNoon: boolean;
  }[];
}

const reference = fixture<LunarFixture>("lunar-reference.json");

describe("lunar calculator matches shared/fixtures/lunar-reference.json", () => {
  test.each(reference.cases)("$name", (c) => {
    const [y, m, d] = c.date.split("-").map(Number);
    const start = zonedInstant(y, m, d, 0, 0, c.timeZone);
    const events = lunarEvents(start, addDays(start, 1, c.timeZone), c);
    expect(events.map((e) => e.event)).toEqual(c.events.map((e) => e.event));
    events.forEach((e, i) => {
      expect(Math.abs(e.date - instant(c.events[i].time)) / 1000, e.event).toBeLessThanOrEqual(reference.toleranceSeconds);
    });
    const phase = moonPhase(dayAt(start, 0, 12, 0, c.timeZone));
    expect(Math.abs(phase.illumination - c.illuminationAtNoon)).toBeLessThanOrEqual(reference.illuminationTolerance);
    expect(phase.isWaxing).toBe(c.waxingAtNoon);
  });
});

test("phase names", () => {
  expect(phaseName({ illumination: 0.01, isWaxing: true })).toBe("New moon");
  expect(phaseName({ illumination: 0.5, isWaxing: true })).toBe("First quarter");
  expect(phaseName({ illumination: 0.8, isWaxing: false })).toBe("Waning gibbous");
  expect(phaseName({ illumination: 0.99, isWaxing: false })).toBe("Full moon");
});

test("the moon ring peaks at the top and rises where the events say", () => {
  const seattle = { latitude: 47.61, longitude: -122.33 };
  const now = instant("2026-11-24T12:00:00-08:00");
  const model = moonDialModel(now, seattle);
  expect(dialAltitude(model, 0)).toBeGreaterThan(dialAltitude(model, 90));
  expect(dialAltitude(model, 0)).toBeGreaterThan(dialAltitude(model, -90));
  expect(model.riseSetAngle).toBeDefined();
  expect(Math.abs(dialAltitude(model, model.riseSetAngle!) - model.riseSetAltitude)).toBeLessThan(0.01);
  expect(Math.abs(model.altitudeNow - moonAltitude(now, seattle))).toBeLessThan(0.01);
});

test("moon colors brighten with height and fullness", () => {
  const low = moonRingColor(5, 0.1, 1, false);
  const high = moonRingColor(50, 0.1, 1, false);
  const newHigh = moonRingColor(50, 0.1, 0, false);
  expect(high[2]).toBeGreaterThan(low[2]);
  expect(high[2]).toBeGreaterThan(newHigh[2]);
});
