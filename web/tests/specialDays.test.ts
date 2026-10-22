import { expect, test } from "vitest";
import { skyEventOnDay, skyOccurrences, skyTitle, skyUpcoming } from "../src/core/skyCalendar";
import { headsUp, nextEclipse, specialToday } from "../src/core/specialDay";
import { instant } from "./fixtures";

// Against PyEphem for 2026.
const tolerance = 15 * 60_000;
const pacific = "America/Los_Angeles";
const seattle = { latitude: 47.61, longitude: -122.33 };
const year = () => skyOccurrences(instant("2026-01-01T00:00:00Z"), instant("2027-01-01T00:00:00Z"), "UTC");

test("seasons", () => {
  const expected: [string, string][] = [
    ["marchEquinox", "2026-03-20T14:45:53Z"], ["juneSolstice", "2026-06-21T08:24:31Z"],
    ["septemberEquinox", "2026-09-23T00:05:09Z"], ["decemberSolstice", "2026-12-21T20:50:00Z"],
  ];
  const seasons = year().filter((o) => o.kind.type === "season");
  expect(seasons).toHaveLength(4);
  for (const [season, iso] of expected) {
    const found = seasons.find((o) => o.kind.type === "season" && o.kind.season === season)!;
    expect(Math.abs(found.date - instant(iso))).toBeLessThan(tolerance);
  }
});

test("full moons, supermoons and the blue moon", () => {
  const fulls = year().filter((o) => o.kind.type === "fullMoon");
  expect(fulls).toHaveLength(13);
  const dec24 = fulls.at(-1)!;
  expect(Math.abs(dec24.date - instant("2026-12-24T01:28:09Z"))).toBeLessThan(tolerance);
  expect(dec24.kind).toEqual({ type: "fullMoon", supermoon: true, blueMoon: false });
  const blue = fulls.filter((o) => o.kind.type === "fullMoon" && o.kind.blueMoon);
  expect(blue).toHaveLength(1);
  expect(Math.abs(blue[0].date - instant("2026-05-31T08:45:08Z"))).toBeLessThan(tolerance);
  expect(skyTitle(blue[0], false)).toBe("Blue moon");
});

test("day lookup uses local dates", () => {
  // The Dec 24 01:28 UTC full moon is on Dec 23 in Seattle.
  expect(skyTitle(skyEventOnDay(instant("2026-12-23T12:00:00-08:00"), pacific)!, false)).toBe("Supermoon");
  expect(skyEventOnDay(instant("2026-12-24T12:00:00-08:00"), pacific)).toBeUndefined();
  const june = skyEventOnDay(instant("2026-06-21T12:00:00-07:00"), pacific)!;
  expect(skyTitle(june, false)).toBe("Summer solstice");
  expect(skyTitle(june, true)).toBe("Winter solstice");
});

test("heads-up", () => {
  expect(skyUpcoming(instant("2026-12-20T12:00:00-08:00"), 3, pacific)?.kind).toEqual({ type: "season", season: "decemberSolstice" });
  expect(skyUpcoming(instant("2026-12-12T12:00:00-08:00"), 3, pacific)).toBeUndefined();
  expect(headsUp(seattle, instant("2026-03-01T20:00:00-08:00"), pacific)).toBe("Total lunar eclipse in 2 days");
});

test("eclipses become the special day", () => {
  expect(specialToday(seattle, instant("2026-03-03T03:30:00-08:00"), pacific)?.title).toBe("Total lunar eclipse");
  const dallas = specialToday({ latitude: 32.78, longitude: -96.8 }, instant("2024-04-08T13:41:00-05:00"), "America/Chicago");
  expect(dallas?.style).toBe("solarEclipse");
  expect(dallas?.title).toBe("Total solar eclipse");
  expect(nextEclipse(instant("2026-01-01T00:00:00-08:00"), seattle, pacific)?.type).toBe("lunar");
});
