# SunClock for the web

The solar dial, readouts, sun and moon events, special sky days and eclipses, in the
browser. Plain TypeScript and canvas, built with Vite; no runtime dependencies.

- `src/core/`: the math, ported from `ios/SunCore` (NOAA sun, Meeus moon, eclipses,
  special days). Tested against the same `shared/fixtures` as iOS, so the platforms
  can't drift apart.
- `src/render/`: the dial, sun and moon drawing (ported from `ios/Shared`).
- `src/main.ts`: the page.
- `public/`: images. The Earth, night-lights and sky maps come from NASA (see the root
  README); the star map is fetched and converted by `.github/workflows/nasa-assets.yml`.
  Commits made by that workflow don't start other workflows, so the next push to `web/`
  is what deploys a refreshed image.

Light and dark follow the system; the Auto / Light / Dark control overrides it (saved
in this browser). Everything runs locally: the location is rounded to about a kilometer
and stays in the browser's storage.

## Run it

```sh
cd web
npm install
npm run dev        # http://localhost:5173
npm test           # fixture tests
npm run build      # static site in dist/
```

Query parameters pin a place, time or look without saving anything, which is handy for
links and screenshots:

```
?lat=47.61&lon=-122.33&name=Seattle&tz=America/Los_Angeles
 &date=2026-03-03T03:30:00-08:00   freeze the clock
 &theme=dark                       system | light | dark
 &display=twelveHour               relative | twelveHour | twentyFourHour
 &dial=now                         noon (solar noon at the top) | now (the dial turns)
 &moon=sky                         clock (moon on the sun's hours) | sky (moon at its angle from the sun)
 &scrub=90                         minutes from the pinned time
```

## CI

`.github/workflows/web.yml` typechecks, runs the tests and builds on every change, then
captures screenshots in Chromium (light and dark, phone and desktop) to the
`screenshots-web` branch. Deploying to GitHub Pages (docs at the site root, the app at
`/app/`) turns on once Pages uses GitHub Actions and the `PAGES_DEPLOY` variable is set.

## Not here (yet)

Alarms: a web page can't ring reliably when it isn't open, so alarms stay on the phone.
With the sync backend (backlog P1-P3) the web app could edit them.
