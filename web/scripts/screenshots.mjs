// Captures the web app in light and dark at phone and desktop widths, for CI and review.
// Usage: node scripts/screenshots.mjs <base url> <output dir>
import { mkdirSync } from "node:fs";
import { chromium } from "playwright";

const [base = "http://localhost:4173/", out = "screenshots"] = process.argv.slice(2);
mkdirSync(out, { recursive: true });

const seattle = "lat=47.61&lon=-122.33&name=Seattle&tz=America/Los_Angeles";
const shots = [
  ["web-1-seattle-june-light", "light", `${seattle}&date=2026-06-21T15:00:00-07:00`],
  ["web-2-seattle-june-dark", "dark", `${seattle}&date=2026-06-21T15:00:00-07:00&display=twelveHour`],
  ["web-3-seattle-december-night-dark", "dark", `${seattle}&date=2026-12-21T21:30:00-08:00&display=twentyFourHour`],
  ["web-4-tromso-midnight-sun-light", "light", "lat=69.65&lon=18.96&name=Tromsø&tz=Europe/Oslo&date=2026-06-21T23:30:00%2B02:00"],
  ["web-5-supermoon-dark", "dark", `${seattle}&date=2026-12-23T20:00:00-08:00`],
  ["web-6-blood-moon-dark", "dark", `${seattle}&date=2026-03-03T03:30:00-08:00`],
  ["web-7-total-solar-eclipse-light", "light", "lat=32.78&lon=-96.80&name=Dallas&tz=America/Chicago&date=2024-04-08T13:41:00-05:00"],
  ["web-8-summer-solstice-light", "light", `${seattle}&date=2026-06-21T16:00:00-07:00`],
  ["web-9-new-moon-dark", "dark", `${seattle}&date=2026-12-08T23:00:00-08:00`],
  ["web-10-welcome-light", "light", ""],
  ["web-11-now-at-top-light", "light", `${seattle}&date=2026-06-21T15:00:00-07:00&dial=now`],
  ["web-12-now-at-top-night-dark", "dark", `${seattle}&date=2026-11-24T22:00:00-08:00&dial=now`],
];

const browser = await chromium.launch();
let failures = 0;
for (const [viewport, size] of [["phone", { width: 390, height: 1500 }], ["desktop", { width: 1100, height: 1300 }]]) {
  for (const [name, scheme, query] of shots) {
    if (viewport === "desktop" && !["web-1-seattle-june-light", "web-2-seattle-june-dark"].includes(name)) continue;
    const context = await browser.newContext({ viewport: size, colorScheme: scheme, deviceScaleFactor: 2, timezoneId: "America/Los_Angeles" });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
    await page.goto(`${base}?${query}`, { waitUntil: "networkidle" });
    await page.waitForTimeout(400);
    await page.screenshot({ path: `${out}/${name}${viewport === "desktop" ? "-desktop" : ""}.png`, fullPage: true });
    if (errors.length) {
      failures++;
      console.error(`${name}: ${errors.join("; ")}`);
    } else {
      console.log(`captured ${name} (${viewport})`);
    }
    await context.close();
  }
}
await browser.close();
process.exit(failures ? 1 : 0);
