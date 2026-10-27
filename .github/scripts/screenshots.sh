#!/usr/bin/env bash
# Build SunClock for a simulator and capture screenshots in demo mode (a fixed place
# and time from launch arguments; see ios/SunClock/App/DemoConfig.swift).
# Usage: screenshots.sh <simulator-udid> <output-dir> [appstore]
#   appstore: only the App Store marketing set (run it on a 6.9" iPhone).
set -euo pipefail
udid=$1
out=$2
mode=${3:-all}
bundle=com.kray.circadian
mkdir -p "$out"

# One simulator at a time: with several booted, xcodebuild sometimes can't find the new
# one. The build is for a generic simulator (no device lookup) and is reused by later
# runs of this script.
xcrun simctl shutdown all 2>/dev/null || true
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

xcodebuild build -quiet \
  -workspace ios/SunClock.xcworkspace -scheme SunClock \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/screenshots \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$udid" build/screenshots/Build/Products/Debug-iphonesimulator/SunClock.app

# shoot <name> <light|dark> <time zone> <ISO date> <app args...>
shoot() {
  local name=$1 appearance=$2 tz=$3 date=$4
  shift 4
  xcrun simctl ui "$udid" appearance "$appearance"
  # The status bar clock is cosmetic, so a rejected override must not stop the run.
  local utc
  utc=$(python3 -c 'import sys, datetime; print(datetime.datetime.fromisoformat(sys.argv[1]).astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$date")
  xcrun simctl status_bar "$udid" override --time "$utc" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 \
    || echo "warning: status bar override failed; continuing"
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  local launched pid
  launched=$(SIMCTL_CHILD_TZ="$tz" xcrun simctl launch "$udid" "$bundle" -demoDate "$date" "$@")
  pid=${launched##*: }
  sleep 5
  # Simulator apps are host processes, so a crash shows up as a missing pid.
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "::error::SunClock exited or crashed while capturing $name"
    report=$(ls -t ~/Library/Logs/DiagnosticReports/SunClock*.ips 2>/dev/null | head -1)
    [[ -n "$report" ]] && head -c 6000 "$report"
    failures=$((failures + 1))
  fi
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
  echo "captured $name (pid $pid)"
}
failures=0

seattle=(-demoLatitude 47.61 -demoLongitude -122.33 -demoName Seattle)
if [[ $mode == appstore ]]; then
  shoot 1-dial-summer-afternoon light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}"
  shoot 2-full-moon-night       dark  America/Los_Angeles 2026-11-24T22:00:00-08:00 "${seattle[@]}"
  shoot 3-events-and-moon       light America/Los_Angeles 2026-11-01T09:00:00-08:00 "${seattle[@]}" -demoScroll moon
  shoot 4-solar-alarms          light America/Los_Angeles 2026-06-20T12:00:00-07:00 "${seattle[@]}" -demoTab alarms
  shoot 5-new-alarm             dark  America/Los_Angeles 2026-06-20T12:00:00-07:00 "${seattle[@]}" -demoTab alarms -demoSheet alarm
  (( failures == 0 )) || exit 1
  exit 0
fi
tromso=(-demoLatitude 69.65 -demoLongitude 18.96 -demoName Tromsø)
shoot 1-seattle-june-afternoon-light light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}"
shoot 2-seattle-june-afternoon-dark  dark  America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoTimeDisplay twelveHour
shoot 3-seattle-december-night-dark  dark  America/Los_Angeles 2026-12-21T21:30:00-08:00 "${seattle[@]}" -demoTimeDisplay twentyFourHour
shoot 4-tromso-midnight-sun-light    light Europe/Oslo         2026-06-21T23:30:00+02:00 "${tromso[@]}"
shoot 5-tromso-polar-night-dark      dark  Europe/Oslo         2026-12-21T12:00:00+01:00 "${tromso[@]}"
shoot 6-location-settings-light      light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoSheet location
shoot 7-alarms-light                 light America/Los_Angeles 2026-06-20T12:00:00-07:00 "${seattle[@]}" -demoTab alarms
shoot 8-alarms-dark                  dark  America/Los_Angeles 2026-06-20T12:00:00-07:00 "${seattle[@]}" -demoTab alarms
shoot 9-new-alarm-light              light America/Los_Angeles 2026-06-20T12:00:00-07:00 "${seattle[@]}" -demoTab alarms -demoSheet alarm
shoot 12-seattle-full-moon-night-dark dark America/Los_Angeles 2026-11-24T22:00:00-08:00 "${seattle[@]}"
shoot 13-seattle-moon-list-light     light America/Los_Angeles 2026-11-01T09:00:00-08:00 "${seattle[@]}" -demoScroll moon
# Special sky days
shoot 15-summer-solstice-light       light America/Los_Angeles 2026-06-21T16:00:00-07:00 "${seattle[@]}"
shoot 16-equinox-dark                dark  America/Los_Angeles 2026-09-22T18:30:00-07:00 "${seattle[@]}"
shoot 17-supermoon-dark              dark  America/Los_Angeles 2026-12-23T20:00:00-08:00 "${seattle[@]}"
shoot 18-blue-moon-dark              dark  America/Los_Angeles 2026-05-31T22:00:00-07:00 "${seattle[@]}"
shoot 19-new-moon-dark               dark  America/Los_Angeles 2026-12-08T23:00:00-08:00 "${seattle[@]}" -demoTimeDisplay twelveHour
shoot 20-heads-up-light              light America/Los_Angeles 2026-12-19T12:00:00-08:00 "${seattle[@]}"
# Eclipses
dallas=(-demoLatitude 32.78 -demoLongitude -96.80 -demoName Dallas)
shoot 21-blood-moon-dark             dark  America/Los_Angeles 2026-03-03T03:30:00-08:00 "${seattle[@]}"
shoot 22-partial-solar-eclipse-light light America/Los_Angeles 2023-10-14T09:18:00-07:00 "${seattle[@]}"
shoot 23-total-solar-eclipse-light   light America/Chicago     2024-04-08T13:41:00-05:00 "${dallas[@]}"
shoot 24-eclipse-heads-up-dark       dark  America/Los_Angeles 2026-03-01T20:00:00-08:00 "${seattle[@]}"
# The rotating dial: now at the top
shoot 25-now-at-top-light            light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoDialOrientation nowAtTop
shoot 26-now-at-top-night-dark       dark  America/Los_Angeles 2026-11-24T22:00:00-08:00 "${seattle[@]}" -demoDialOrientation nowAtTop
# The moon where it is in the sky (its angle from the sun shows the phase)
shoot 27-moon-in-sky-light           light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoMoonPlacement sky
shoot 28-moon-in-sky-full-dark       dark  America/Los_Angeles 2026-11-24T22:00:00-08:00 "${seattle[@]}" -demoMoonPlacement sky -demoDialOrientation nowAtTop
shoot 29-hand-gold-dark              dark  America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoHandColor gold
shoot 30-hand-cyan-light             light America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoHandColor cyan
shoot 31-sun-periods-light           light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoTimeDisplay periods
shoot 32-wadokei-molten-dark         dark  America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoTimeDisplay wadokei
shoot 33-wadokei-gold-light          light America/Los_Angeles 2026-03-20T09:00:00-07:00 "${seattle[@]}" -demoTimeDisplay wadokei -demoKanjiStyle gold
shoot 34-wadokei-plain-night-dark    dark  America/Los_Angeles 2026-12-21T23:30:00-08:00 "${seattle[@]}" -demoTimeDisplay wadokei -demoKanjiStyle plain
# Largest accessibility text size, to check nothing truncates.
xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
shoot 14-accessibility-text-light    light America/Los_Angeles 2026-11-01T09:00:00-08:00 "${seattle[@]}" -demoScroll moon
xcrun simctl ui "$udid" content_size large
shoot 10-widgets-light               light America/Los_Angeles 2026-06-21T15:00:00-07:00 "${seattle[@]}" -demoSheet widgets
shoot 11-widgets-dark-evening        dark  America/Los_Angeles 2026-12-21T17:00:00-08:00 "${seattle[@]}" -demoSheet widgets

if (( failures > 0 )); then
  echo "$failures screenshot(s) caught a crashed app"
  exit 1
fi
