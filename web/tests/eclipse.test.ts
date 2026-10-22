import { describe, expect, test } from "vitest";
import { lunarEclipse, lunarEclipses, solarEclipse, solarEclipses, umbralCoverage } from "../src/core/eclipse";
import { skyOccurrences } from "../src/core/skyCalendar";
import { fixture, instant } from "./fixtures";

interface EclipseFixture {
  toleranceSeconds: number;
  magnitudeTolerance: number;
  lunar: { date: string; kind: string; greatest: string; umbralMagnitude: number; contacts: Record<string, string> }[];
  solar: {
    name: string; latitude: number; longitude: number; date: string; kind: string | null;
    maximum?: string; start?: string; end?: string; magnitude?: number; obscuration?: number; centralStart?: string;
  }[];
}

const reference = fixture<EclipseFixture>("eclipse-reference.json");
const seconds = (a: number, b: number) => Math.abs(a - b) / 1000;

describe("lunar eclipses match shared/fixtures/eclipse-reference.json", () => {
  test.each(reference.lunar)("$kind lunar $date", (c) => {
    const e = lunarEclipse(instant(c.greatest))!;
    expect(e).toBeDefined();
    expect(e.kind).toBe(c.kind);
    expect(seconds(e.greatest, instant(c.greatest))).toBeLessThanOrEqual(reference.toleranceSeconds);
    expect(Math.abs(e.umbralMagnitude - c.umbralMagnitude)).toBeLessThanOrEqual(reference.magnitudeTolerance);
    const contacts: Record<string, number | undefined> = {
      Pstart: e.penumbralStart, Pend: e.penumbralEnd, Ustart: e.partialStart, Uend: e.partialEnd, Tstart: e.totalStart, Tend: e.totalEnd,
    };
    for (const [name, iso] of Object.entries(c.contacts)) {
      expect(contacts[name], name).toBeDefined();
      expect(seconds(contacts[name]!, instant(iso)), name).toBeLessThanOrEqual(reference.toleranceSeconds);
    }
  });
});

describe("solar eclipses match shared/fixtures/eclipse-reference.json", () => {
  test.each(reference.solar)("$name", (c) => {
    const day = instant(`${c.date}T12:00:00Z`);
    const newMoon = skyOccurrences(day - 86_400_000, day + 86_400_000, "UTC").find((o) => o.kind.type === "newMoon")!;
    const e = solarEclipse(newMoon.date, c);
    if (c.kind === null) {
      expect(e).toBeUndefined();
      return;
    }
    expect(e).toBeDefined();
    expect(e!.kind).toBe(c.kind);
    expect(seconds(e!.maximum, instant(c.maximum!))).toBeLessThanOrEqual(reference.toleranceSeconds);
    expect(seconds(e!.start, instant(c.start!))).toBeLessThanOrEqual(reference.toleranceSeconds);
    expect(seconds(e!.end, instant(c.end!))).toBeLessThanOrEqual(reference.toleranceSeconds);
    expect(Math.abs(e!.magnitude - c.magnitude!)).toBeLessThanOrEqual(reference.magnitudeTolerance);
    expect(Math.abs(e!.obscuration - c.obscuration!)).toBeLessThanOrEqual(reference.magnitudeTolerance);
    if (c.centralStart) expect(seconds(e!.centralStart!, instant(c.centralStart))).toBeLessThanOrEqual(reference.toleranceSeconds);
  });
});

test("searching finds the year's eclipses", () => {
  expect(lunarEclipses(instant("2026-01-01T00:00:00Z"), instant("2027-01-01T00:00:00Z")).map((e) => e.kind)).toEqual(["total", "partial"]);
  const dallas = { latitude: 32.78, longitude: -96.8 };
  expect(solarEclipses(instant("2024-01-01T00:00:00Z"), instant("2025-01-01T00:00:00Z"), dallas).map((e) => e.kind)).toEqual(["total"]);
});

test("coverage during totality", () => {
  const e = lunarEclipse(instant("2026-03-03T11:33:00Z"))!;
  expect(umbralCoverage(e.totalStart! + 60_000)).toBeGreaterThan(0.99);
  expect(umbralCoverage(e.penumbralStart)).toBe(0);
});
