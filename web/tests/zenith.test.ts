import { describe, expect, test } from "vitest";
import { sunPosition } from "../src/core/solar";
import { nextZenithPassage, zenithPassages } from "../src/core/zenith";
import { instant } from "./fixtures";

const year = (y: number) => [instant(`${y}-01-01T00:00:00Z`), instant(`${y + 1}-01-01T00:00:00Z`)] as const;
const isoDay = (t: number, tz: string) => new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(t);

describe("zenith passage", () => {
  test("twice a year between the tropics, on the days the noon sun is overhead", () => {
    // Mérida, Yucatán (20.97° N). Dates checked with PyEphem: the noon sun peaks at
    // 89.92° on May 25 and 89.95° on July 18.
    const merida = { latitude: 20.97, longitude: -89.62 };
    const passages = zenithPassages(...year(2026), merida);
    expect(passages.map((p) => isoDay(p.date, "America/Merida"))).toEqual(["2026-05-25", "2026-07-18"]);
    for (const p of passages) {
      expect(p.altitude).toBeGreaterThan(89.75);
      expect(Math.abs(sunPosition(p.date).declination - merida.latitude)).toBeLessThan(0.25);
    }
    expect(isoDay(nextZenithPassage(passages[0].date, merida)!.date, "America/Merida")).toBe("2026-07-18");
    expect(isoDay(nextZenithPassage(passages[1].date, merida)!.date, "America/Merida").slice(0, 7)).toBe("2027-05");
  });

  test("the southern tropics too", () => {
    // Rio de Janeiro (22.91° S), either side of the December solstice (PyEphem: January 2
    // and December 10).
    const rio = { latitude: -22.91, longitude: -43.17 };
    const passages = zenithPassages(...year(2026), rio);
    expect(passages.map((p) => isoDay(p.date, "America/Sao_Paulo"))).toEqual(["2026-01-02", "2026-12-10"]);
  });

  test("on the equator, near the equinoxes", () => {
    const quito = { latitude: -0.18, longitude: -78.47 };
    const months = zenithPassages(...year(2026), quito).map((p) => isoDay(p.date, "America/Guayaquil").slice(5, 7));
    expect(months).toEqual(["03", "09"]);
  });

  test("never outside the tropics", () => {
    expect(zenithPassages(...year(2026), { latitude: 47.61, longitude: -122.33 })).toEqual([]);
    expect(zenithPassages(...year(2026), { latitude: 25.0, longitude: 55.3 })).toEqual([]);
  });
});
