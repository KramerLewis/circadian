// SunClock for the web: wires the core math and the dial renderer to the page.

import { dialAltitude, dialModel, moonDialModel } from "./core/dial";
import { solarCoverage, umbralCoverage } from "./core/eclipse";
import { clockTime, longDate, shortDate } from "./core/format";
import { lunarEventNames, lunarEvents, phaseName } from "./core/lunar";
import type { Coordinate } from "./core/math";
import { duration, readout, solarClock } from "./core/readout";
import { apparentSolarMinutes, eventNames, isInstant, solarDayContaining, solarEvents, solarHourAngle } from "./core/solar";
import { type SpecialDay, type SpecialStyle, eclipseDate, fromEclipse, headsUp, nextEclipse, specialToday } from "./core/specialDay";
import { browserTimeZone, startOfDay } from "./core/tz";
import { type Period, moonPeriod, sunPeriod, wadokeiHours } from "./core/periods";
import { type WadokeiScene, drawWadokei } from "./render/wadokei";
import { zodiacNames } from "./render/zodiac";
import { type HandColor, dialGeometry, drawDial, drawHand, drawMoon, handColors } from "./render/dial";
import { loadMoonTexture } from "./render/moon";
import {
  defaultOrbitCamera, drawOrbit, loadOrbitTextures, loadSunImage, rollOrbitCamera, setNorthUp, turnOrbitCamera,
  turnOrbitCameraNorthUp,
} from "./render/orbit";
import { loadSunSpots } from "./render/sun";

// MARK: State

interface Place extends Coordinate {
  name: string;
  timeZone: string;
}

type TimeDisplay = "relative" | "twelveHour" | "twentyFourHour" | "periods" | "wadokei";
type Theme = "system" | "light" | "dark";
type Orientation = "noon" | "now";
type MoonMode = "clock" | "sky";

const displays: TimeDisplay[] = ["relative", "twelveHour", "twentyFourHour", "periods", "wadokei"];
const displayTitles: Record<TimeDisplay, string> = {
  relative: "Relative to the sun",
  twelveHour: "12-hour clock",
  twentyFourHour: "24-hour clock",
  periods: "Sun periods",
  wadokei: "Wadokei (Edo temporal hours)",
};

/** Browser storage can be unavailable (private windows, blocked site data). */
const storage = {
  get<T>(key: string): T | undefined {
    try {
      const raw = localStorage.getItem(`sunclock.${key}`);
      return raw ? (JSON.parse(raw) as T) : undefined;
    } catch {
      return undefined;
    }
  },
  set(key: string, value: unknown) {
    try {
      localStorage.setItem(`sunclock.${key}`, JSON.stringify(value));
    } catch {
      /* not saved; the page still works */
    }
  },
};

// Query parameters set a place, time, theme or display without saving them, for links
// and screenshots: ?lat=47.61&lon=-122.33&name=Seattle&tz=America/Los_Angeles&date=2026-06-21T15:00:00-07:00
const params = new URLSearchParams(location.search);
const paramPlace = ((): Place | undefined => {
  const latitude = Number(params.get("lat")), longitude = Number(params.get("lon"));
  if (!params.has("lat") || !params.has("lon") || !isValid(latitude, longitude)) return undefined;
  return { name: params.get("name") ?? "Pinned place", latitude, longitude, timeZone: validTimeZone(params.get("tz")) };
})();
const frozenNow = params.has("date") ? Date.parse(params.get("date")!) : NaN;

const state = {
  place: paramPlace ?? storage.get<Place>("place"),
  display: (params.get("display") as TimeDisplay) ?? storage.get<TimeDisplay>("display") ?? "relative",
  theme: (params.get("theme") as Theme) ?? storage.get<Theme>("theme") ?? "system",
  orientation: (params.get("dial") as Orientation) ?? storage.get<Orientation>("orientation") ?? "noon",
  moonMode: (params.get("moon") as MoonMode) ?? storage.get<MoonMode>("moonMode") ?? "clock",
  handColor: (params.get("hand") as HandColor) ?? storage.get<HandColor>("handColor") ?? "royalBlue",
  moonPeriods: params.has("moonp") ? params.get("moonp") === "1" : (storage.get<boolean>("moonPeriods") ?? false),
  scrubMinutes: Number(params.get("scrub") ?? 0),
};
if (!displays.includes(state.display)) state.display = "relative";
if (state.orientation !== "now") state.orientation = "noon";
if (state.moonMode !== "sky") state.moonMode = "clock";
if (!handColors.some((c) => c.id === state.handColor)) state.handColor = "royalBlue";

function isValid(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180;
}

function validTimeZone(tz: string | null | undefined): string {
  if (!tz) return browserTimeZone();
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return browserTimeZone();
  }
}

const baseNow = () => (Number.isFinite(frozenNow) ? frozenNow : Date.now());

// MARK: Elements

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const dial = $<HTMLCanvasElement>("dial");
const scrubber = $<HTMLInputElement>("scrubber");
const nowButton = $<HTMLButtonElement>("now-button");
const dialog = $<HTMLDialogElement>("place-dialog");
const form = $<HTMLFormElement>("place-form");
const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");

// MARK: Theme

function applyTheme() {
  if (state.theme === "system") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = state.theme;
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-theme-choice]")) {
    button.setAttribute("aria-checked", String(button.dataset.themeChoice === state.theme));
  }
}

const isDark = () => state.theme === "dark" || (state.theme === "system" && darkQuery.matches);

// MARK: Rendering

const specialStyles: Record<SpecialStyle, { color: string; icon: string }> = {
  solstice: { color: "#f29d1b", icon: "sun" },
  equinox: { color: "#d8a64a", icon: "half" },
  fullMoon: { color: "#8a93b8", icon: "moon" },
  supermoon: { color: "#7d8bd6", icon: "moon" },
  blueMoon: { color: "#4f7bf0", icon: "moon" },
  newMoon: { color: "#7373d9", icon: "stars" },
  lunarEclipse: { color: "#d9402e", icon: "moon" },
  solarEclipse: { color: "#f2b326", icon: "eclipse" },
};

const icons: Record<string, string> = {
  sun: '<circle cx="12" cy="12" r="4.5"/><g stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8"/></g>',
  half: '<path d="M12 3a9 9 0 0 0 0 18Z"/><circle cx="12" cy="12" r="8.2" fill="none" stroke="currentColor" stroke-width="1.6"/>',
  moon: '<path d="M14.5 3.2A9 9 0 1 0 20.8 15 7.2 7.2 0 0 1 14.5 3.2Z"/>',
  stars: '<path d="M14.5 3.2A9 9 0 1 0 20.8 15 7.2 7.2 0 0 1 14.5 3.2Z"/><path d="M18 3l.7 1.6L20.3 5l-1.6.7L18 7.3l-.7-1.6L15.7 5l1.6-.4Z"/>',
  eclipse: '<circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-dasharray="2.4 2"/><circle cx="13.5" cy="11" r="6"/>',
};
const svg = (name: string) => `<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor" aria-hidden="true">${icons[name]}</svg>`;

const dayCache = new Map<string, { special?: SpecialDay; headsUp?: string }>();

function specialFor(place: Place, now: number) {
  const key = `${startOfDay(now, place.timeZone)}|${place.latitude}|${place.longitude}|${place.timeZone}`;
  let entry = dayCache.get(key);
  if (!entry) {
    const special = specialToday(place, now, place.timeZone);
    entry = { special, headsUp: special ? undefined : headsUp(place, now, place.timeZone) };
    if (dayCache.size > 16) dayCache.clear();
    dayCache.set(key, entry);
  }
  return entry;
}

function centerText(now: number, place: Place, r: ReturnType<typeof readout>): [string, string] {
  const solar = `${solarClock(apparentSolarMinutes(now, place.longitude))} solar`;
  switch (state.display) {
    case "relative":
      if (!r.nearestAnchor) return [solar, ""];
      return [duration(r.nearestAnchor.interval), `${r.nearestAnchorIsPast ? "after" : "until"} ${eventNames[r.nearestAnchor.event].toLowerCase()}`];
    case "twelveHour":
      return [clockTime(now, place.timeZone, "twelveHour"), solar];
    case "twentyFourHour":
      return [clockTime(now, place.timeZone, "twentyFourHour"), solar];
    case "periods": {
      const p = sunPeriod(now, place);
      return p ? [p.code, periodPhrase(p)] : [solar, ""];
    }
    case "wadokei":
      // The kanji and animal are drawn on the wadokei layer instead.
      return ["", ""];
  }
}

function render() {
  const place = state.place;
  $("welcome").hidden = !!place;
  $("today").hidden = !place;
  $("place-name").textContent = place?.name ?? "Choose a place";
  if (!place) return;

  const tz = place.timeZone;
  const now = baseNow() + state.scrubMinutes * 60_000;
  const day = solarDayContaining(now, place);
  const model = dialModel(day, now);
  const moon = moonDialModel(now, place);
  const r = readout(now, place);
  const { special, headsUp: upcoming } = specialFor(place, now);
  const styles = getComputedStyle(document.documentElement);

  // Size the readout to the space inside the hour labels, which turn with the dial.
  const inner = dialGeometry(dial.clientWidth).moonInner;
  const center = $("dial-center");
  center.style.width = `${inner * 1.6}px`;
  center.style.setProperty("--primary-size", `${Math.min(34, inner * 0.3)}px`);
  center.style.setProperty("--secondary-size", `${Math.min(18, Math.max(11, inner * 0.15))}px`);
  const [primary, secondary] = centerText(now, place, r);
  $("center-primary").textContent = primary;
  $("center-secondary").textContent = secondary;
  const primaryBox = $("center-primary").getBoundingClientRect(), secondaryBox = $("center-secondary").getBoundingClientRect();
  const readoutBox = {
    halfWidth: Math.max(primaryBox.width, secondaryBox.width) / 2,
    halfHeight: (primaryBox.height + secondaryBox.height) / 2,
  };
  drawDial(dial, {
    model,
    moon,
    dark: isDark(),
    colors: { primary: styles.getPropertyValue("--text").trim(), secondary: styles.getPropertyValue("--muted").trim() },
    special: special?.style,
    eclipseShadow: special?.style === "lunarEclipse" ? umbralCoverage(now) : 0,
    solarEclipse: special?.style === "solarEclipse" ? solarCoverage(now, place) : undefined,
    label: (date) => clockTime(date, tz),
    eventLabels: state.display !== "wadokei",
    sectionTicks: sectionTicks(now, place),
    orientation: state.orientation,
    moonMode: state.moonMode,
    readout: readoutBox,
  });
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-dial-choice]")) {
    button.setAttribute("aria-checked", String(button.dataset.dialChoice === state.orientation));
  }
  handScene = { model, orientation: state.orientation, dark: isDark() };
  drawHand(handCanvas, handScene, state.handColor, shimmerPhase());
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-moon-choice]")) {
    button.setAttribute("aria-checked", String(button.dataset.moonChoice === state.moonMode));
  }
  // The sky view's moon ticks don't line up with the hours, so say when they are.
  const moonTimes = $("moon-times");
  const times = [
    moon.sky.nextRise !== undefined ? { at: moon.sky.nextRise, text: `Moonrise ${clockTime(moon.sky.nextRise, tz)}` } : undefined,
    moon.sky.nextSet !== undefined ? { at: moon.sky.nextSet, text: `Moonset ${clockTime(moon.sky.nextSet, tz)}` } : undefined,
  ].filter((t) => t !== undefined).sort((a, b) => a.at - b.at);
  moonTimes.hidden = state.moonMode !== "sky" || times.length === 0;
  moonTimes.textContent = `Next: ${times.map((t) => t.text).join(" · ")}`;

  const sun = Math.round(dialAltitude(model, model.nowAngle));
  dial.setAttribute(
    "aria-label",
    `Solar dial. ${primary} ${secondary}. ${sun >= 0 ? `Sun ${sun}° up` : `Sun ${-sun}° below the horizon`}. ` +
      `Moon: ${phaseName(moon.phase).toLowerCase()}, ${Math.round(moon.phase.illumination * 100)}% lit, ` +
      `${moon.altitudeNow > moon.riseSetAltitude ? "up" : "below the horizon"}.`,
  );
  $("dial-center").title = `${displayTitles[state.display]} (click to change)`;

  const scrubbing = state.scrubMinutes !== 0;
  $("date-line").textContent = `${longDate(now, tz)}${scrubbing || Number.isFinite(frozenNow) ? ` · ${clockTime(now, tz)}` : ""}`;
  nowButton.disabled = !scrubbing;
  scrubber.value = String(state.scrubMinutes);
  const sign = state.scrubMinutes < 0 ? "−" : "+";
  $("scrub-label").textContent = scrubbing ? `${sign}${duration(Math.abs(state.scrubMinutes) * 60_000)} from now` : "";

  renderOrbit(now, place);
  renderPeriodDetails(now, place);
  wadokeiScene =
    state.display === "wadokei"
      ? { hours: wadokeiRing(now, place), rotation: state.orientation === "now" ? -model.nowAngle : 0, dark: isDark() }
      : undefined;
  drawWadokeiLayer();
  renderSpecial(special, upcoming);
  renderReadouts(now, place, r, day);
  renderEvents(now, tz, day);
  renderMoon(now, place, day);
}

// MARK: Sun periods and wadokei

const milestoneNames: Record<string, string> = {
  R: "sunrise", N: "solar noon", S: "sunset", M: "solar midnight",
  r: "moonrise", n: "the moon's highest", s: "moonset", m: "the moon's lowest",
};
const middleNames: Record<string, string> = { "0": "mid-morning", "1": "mid-afternoon", "2": "mid-evening", "3": "deep night" };
const quarterNames: Record<string, string> = { R: "morning", N: "afternoon", S: "evening", M: "night" };

const nextMilestone: Record<string, string> = { R: "N", N: "S", S: "M", M: "R" };

/** "after solar noon", "around sunset", "mid-afternoon". */
function periodPhrase(p: Period): string {
  const letter = p.code.replace(/[-+]/g, "");
  if (/^\d$/.test(p.code)) {
    // The usual solar quarters have names; the moon's and polar days' are described.
    return nextMilestone[p.from.letter] === p.to.letter
      ? middleNames[p.code]
      : `between ${milestoneNames[p.from.letter]} and ${milestoneNames[p.to.letter]}`;
  }
  if (p.code.startsWith("-")) return `before ${milestoneNames[letter]}`;
  if (p.code.endsWith("+")) return `after ${milestoneNames[letter]}`;
  return `around ${milestoneNames[letter]}`;
}

function sectionTicks(now: number, place: Place): number[] | undefined {
  const angle = (t: number) => solarHourAngle(t, place.longitude);
  if (state.display === "wadokei") return wadokeiHours(now, place).map((h) => angle(h.start));
  if (state.display !== "periods") return undefined;
  const day = solarDayContaining(now, place);
  const ticks: number[] = [];
  // Every boundary in this solar day: walk the periods from its start.
  for (let t = day.solarMidnight + 1, guard = 0; t < day.nextSolarMidnight && guard < 40; guard++) {
    const p = sunPeriod(t, place);
    if (!p) break;
    ticks.push(angle(p.end));
    t = p.end + 1;
  }
  return ticks;
}

function wadokeiRing(now: number, place: Place): WadokeiScene["hours"] {
  const hours = wadokeiHours(now, place);
  const day = solarDayContaining(now, place);
  // One of each animal: the hours overlapping this solar day, nearest to now.
  const seen = new Map<string, WadokeiScene["hours"][number] & { distance: number }>();
  for (const h of hours) {
    const mid = (h.start + h.end) / 2;
    if (h.end < day.solarMidnight || h.start > day.nextSolarMidnight) continue;
    const distance = Math.abs(mid - now);
    const prior = seen.get(h.kanji);
    if (!prior || distance < prior.distance) {
      seen.set(h.kanji, { kanji: h.kanji, angle: solarHourAngle(mid, place.longitude), active: h.start <= now && now < h.end, distance });
    }
  }
  return [...seen.values()];
}

function renderPeriodDetails(now: number, place: Place) {
  const box = $("period-details");
  const tz = place.timeZone;
  const lines: string[] = [];
  if (state.display === "periods") {
    const p = sunPeriod(now, place);
    if (p) {
      const quarter = quarterNames[p.from.letter] ?? "half-day";
      lines.push(`<strong>${p.code}</strong> · ${periodPhrase(p)}`);
      lines.push(
        `${duration(now - p.from.date)} after ${milestoneNames[p.from.letter]} · ${duration(p.to.date - now)} before ${milestoneNames[p.to.letter]} · ` +
          `${Math.round(p.fraction * 100)}% through the ${quarter}`,
      );
      const next = sunPeriod(p.end + 1, place);
      lines.push(`${p.code} until ${clockTime(p.end, tz)}${next ? `, then ${next.code}` : ""} · this section is ${duration(p.end - p.start)} today`);
    }
    if (state.moonPeriods) {
      const m = moonPeriod(now, place);
      if (m) {
        lines.push(
          `Moon <strong>${m.code}</strong> · ${periodPhrase(m)} · ${duration(now - m.from.date)} after ${milestoneNames[m.from.letter]}, ` +
            `${duration(m.to.date - now)} before ${milestoneNames[m.to.letter]}`,
        );
      }
    }
  } else if (state.display === "wadokei") {
    const hours = wadokeiHours(now, place);
    const i = hours.findIndex((h) => h.start <= now && now < h.end);
    const h = hours[i], next = hours[i + 1];
    const counts = ["", "", "", "", "四つ", "五つ", "六つ", "七つ", "八つ", "九つ"];
    if (h) {
      const daylight = "卯辰巳午未申".includes(h.kanji);
      lines.push(`<strong lang="ja">${h.kanji}</strong> ${zodiacNames[h.kanji]} hour (<span lang="ja">${counts[h.count]}</span>, ${h.count}) · ${daylight ? "daylight" : "night"}`);
      lines.push(`${clockTime(h.start, tz)} – ${clockTime(h.end, tz)} · ${duration(h.end - h.start)} long today (an equal hour would be 2h 0m)`);
      if (next) lines.push(`Next: <span lang="ja">${next.kanji}</span> ${zodiacNames[next.kanji]} at ${clockTime(next.start, tz)}`);
      const dawn = hours.find((t) => t.kanji === "卯" && t.end > now - 86_400_000);
      const dusk = hours.find((t) => t.kanji === "酉" && t.start > (dawn?.start ?? 0));
      if (dawn && dusk) {
        lines.push(`Dawn (<span lang="ja">明け六つ</span>) ${clockTime(dawn.start, tz)} · dusk (<span lang="ja">暮れ六つ</span>) ${clockTime(dusk.start, tz)}: the sun 7.4° below the horizon`);
      }
    }
  }
  box.hidden = lines.length === 0;
  box.querySelector(".lines")!.innerHTML = lines.map((l) => `<p>${l}</p>`).join("");
  const toggle = box.querySelector<HTMLLabelElement>(".moon-toggle")!;
  toggle.hidden = state.display !== "periods";
  box.querySelector<HTMLInputElement>("input")!.checked = state.moonPeriods;
}

const wadokeiCanvas = $<HTMLCanvasElement>("wadokei");
let wadokeiScene: WadokeiScene | undefined;
let emberFrame = 0;

function drawWadokeiLayer() {
  wadokeiCanvas.hidden = !wadokeiScene;
  if (!wadokeiScene) return;
  drawWadokei(wadokeiCanvas, wadokeiScene, reduceMotion.matches ? undefined : performance.now() / 1000);
}

/** The embers flicker only in wadokei mode, and only this layer redraws (about 30 fps). */
function embers() {
  cancelAnimationFrame(emberFrame);
  let last = 0;
  const tick = (t: number) => {
    if (state.display === "wadokei" && !reduceMotion.matches) {
      if (t - last > 33 && document.visibilityState === "visible") {
        last = t;
        drawWadokeiLayer();
      }
      emberFrame = requestAnimationFrame(tick);
    }
  };
  emberFrame = requestAnimationFrame(tick);
}

$("period-details").querySelector("input")!.addEventListener("change", (e) => {
  state.moonPeriods = (e.target as HTMLInputElement).checked;
  storage.set("moonPeriods", state.moonPeriods);
  render();
});

// The brush font for the kanji ships with the app (no third-party font service).
new FontFace("SunClock Wadokei", `url(${import.meta.env.BASE_URL}fonts/wadokei.woff2)`)
  .load()
  .then((face) => {
    document.fonts.add(face);
    render();
  }, () => {});

// MARK: Hand

const handCanvas = $<HTMLCanvasElement>("hand");
const handSelect = $<HTMLSelectElement>("hand-color");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let handScene: Parameters<typeof drawHand>[1] | undefined;
let shimmerFrame = 0;

/** Seconds for the gold shimmer, or undefined to hold it still. */
const shimmerPhase = () => (state.handColor === "gold" && !reduceMotion.matches ? performance.now() / 1000 : undefined);

/** Only a gold hand animates, and only it redraws every frame (the dial doesn't). */
function shimmer() {
  cancelAnimationFrame(shimmerFrame);
  if (state.handColor !== "gold" || reduceMotion.matches) return;
  const tick = () => {
    if (handScene && document.visibilityState === "visible") drawHand(handCanvas, handScene, "gold", shimmerPhase());
    shimmerFrame = requestAnimationFrame(tick);
  };
  shimmerFrame = requestAnimationFrame(tick);
}

const displaySelect = $<HTMLSelectElement>("display-select");
displaySelect.innerHTML = displays.map((d) => `<option value="${d}">${displayTitles[d]}</option>`).join("");
displaySelect.value = state.display;
displaySelect.addEventListener("change", () => {
  state.display = displaySelect.value as TimeDisplay;
  storage.set("display", state.display);
  render();
  embers();
});

handSelect.innerHTML = handColors.map((c) => `<option value="${c.id}">${c.title}</option>`).join("");
handSelect.value = state.handColor;
handSelect.addEventListener("change", () => {
  state.handColor = handSelect.value as HandColor;
  storage.set("handColor", state.handColor);
  render();
  shimmer();
});
reduceMotion.addEventListener("change", () => {
  render();
  shimmer();
  embers();
});

// MARK: 3D view

const orbitCanvas = $<HTMLCanvasElement>("orbit");
const orbitCamera = defaultOrbitCamera();
let orbitVisible = false;
let lastOrbit: { now: number; place: Place } | undefined;

const needle = document.getElementById("orbit-north-needle")!;
let northLocked = false;
let northAngle: number | null = 0;

function renderOrbit(now: number, place: Place) {
  lastOrbit = { now, place };
  redrawOrbit();
}

const redrawOrbit = () => {
  // Drawn per pixel, so only while it's on screen.
  if (!lastOrbit || !orbitVisible) return;
  northAngle = drawOrbit(orbitCanvas, { ...lastOrbit, dark: isDark(), camera: orbitCamera });
  // The compass needle points where Earth's north pole points on screen.
  needle.setAttribute("transform", `rotate(${((northAngle ?? 0) * 180) / Math.PI} 16 16)`);
};

new IntersectionObserver((entries) => {
  orbitVisible = entries.some((e) => e.isIntersecting);
  redrawOrbit();
}).observe(orbitCanvas);

{
  // A trackball: one finger (or the mouse) turns the camera about its own axes, with no
  // stop at the poles; two fingers twisting roll it about the way it's looking.
  const pointers = new Map<number, { x: number; y: number }>();
  let pending = 0;
  const redraw = () => {
    cancelAnimationFrame(pending);
    pending = requestAnimationFrame(redrawOrbit);
  };
  const twist = () => {
    const [a, b] = [...pointers.values()];
    return Math.atan2(b.y - a.y, b.x - a.x);
  };
  orbitCanvas.addEventListener("pointerdown", (e) => {
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    try {
      orbitCanvas.setPointerCapture(e.pointerId);
    } catch {
      /* the pointer is already gone; the drag still works without capture */
    }
  });
  orbitCanvas.addEventListener("pointermove", (e) => {
    const previous = pointers.get(e.pointerId);
    if (!previous) return;
    if (pointers.size === 1) {
      const across = -(e.clientX - previous.x) * 0.5, along = (e.clientY - previous.y) * 0.4;
      if (northLocked) turnOrbitCameraNorthUp(orbitCamera, across, along);
      else turnOrbitCamera(orbitCamera, across, along);
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    } else if (pointers.size === 2 && !northLocked) {
      const before = twist();
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      let delta = twist() - before;
      if (delta > Math.PI) delta -= 2 * Math.PI;
      if (delta < -Math.PI) delta += 2 * Math.PI;
      rollOrbitCamera(orbitCamera, (delta * 180) / Math.PI);
    }
    redraw();
  });
  const end = (e: PointerEvent) => pointers.delete(e.pointerId);
  orbitCanvas.addEventListener("pointerup", end);
  orbitCanvas.addEventListener("pointercancel", end);

  // The compass: roll smoothly until north is up (keeping where the view looks from).
  // Tapped again with north already up, it locks north up (the globe-on-a-stand turning
  // from before: no rolling, and it stops short of the poles); tapped once more, unlocks.
  let northAnimation = 0;
  const compass = document.getElementById("orbit-north")!;
  const showLock = () => {
    compass.classList.toggle("locked", northLocked);
    compass.setAttribute("aria-pressed", String(northLocked));
    compass.title = northLocked ? "North locked up (tap to unlock)" : "Turn north up (tap again to lock)";
  };
  showLock();
  compass.addEventListener("click", () => {
    cancelAnimationFrame(northAnimation);
    if (northLocked) {
      northLocked = false;
      showLock();
      return;
    }
    if (northAngle !== null && Math.abs(northAngle) < 0.01) {
      setNorthUp(orbitCamera);
      northLocked = true;
      showLock();
      redrawOrbit();
      return;
    }
    const step = () => {
      if (northAngle === null || Math.abs(northAngle) < 0.002) return;
      const turn = Math.abs(northAngle) < 0.02 ? northAngle : northAngle * 0.25;
      // Rolling the image counter-clockwise by the needle's angle brings north to the top.
      rollOrbitCamera(orbitCamera, (-turn * 180) / Math.PI);
      redrawOrbit();
      northAnimation = requestAnimationFrame(step);
    };
    step();
  });
  orbitCanvas.addEventListener("dblclick", () => {
    Object.assign(orbitCamera, defaultOrbitCamera());
    northLocked = false;
    showLock();
    redrawOrbit();
  });
}

function renderSpecial(special: SpecialDay | undefined, upcoming: string | undefined) {
  const card = $("special");
  card.hidden = !special;
  if (special) {
    const style = specialStyles[special.style];
    card.style.setProperty("--special", style.color);
    $("special-symbol").innerHTML = svg(style.icon);
    $("special-title").textContent = special.title;
    $("special-lines").textContent = special.lines.join(" ");
  }
  const heads = $("heads-up");
  heads.hidden = !upcoming;
  heads.textContent = upcoming ?? "";
}

function renderReadouts(now: number, place: Place, r: ReturnType<typeof readout>, day: ReturnType<typeof solarDayContaining>) {
  const items: [string, string][] = [];
  if (r.polarCondition) {
    items.push([r.polarCondition === "midnightSun" ? "Midnight sun" : "Polar night", r.polarCondition === "midnightSun" ? "The sun doesn't set today" : "The sun doesn't rise today"]);
  }
  if (r.previousHorizon) items.push([duration(r.previousHorizon.interval), `since ${eventNames[r.previousHorizon.event].toLowerCase()}`]);
  if (r.nextHorizon) items.push([duration(r.nextHorizon.interval), `until ${eventNames[r.nextHorizon.event].toLowerCase()}`]);
  const rise = day.events.sunrise, set = day.events.sunset;
  if (isInstant(rise) && isInstant(set)) items.push([duration(set - rise), "of daylight"]);
  items.push([solarClock(apparentSolarMinutes(now, place.longitude)), "solar time"]);
  $("readouts").innerHTML = items
    .map(([value, label]) => `<div class="readout"><div class="value">${escape(value)}</div><div class="label">${escape(label)}</div></div>`)
    .join("");
}

function renderEvents(now: number, tz: string, day: ReturnType<typeof solarDayContaining>) {
  const next = solarEvents.find((e) => {
    const t = day.events[e];
    return isInstant(t) && t > now;
  });
  $("events").innerHTML = solarEvents
    .map((event) => {
      const t = day.events[event];
      const time = isInstant(t) ? clockTime(t, tz) : t === "sunAlwaysAbove" ? "Sun stays above" : "Sun stays below";
      const cls = event === next ? "next" : isInstant(t) && t <= now ? "past" : "";
      return `<li class="${cls}"><span>${eventNames[event]}</span><span class="time">${time}</span></li>`;
    })
    .join("");
}

function renderMoon(now: number, place: Place, day: ReturnType<typeof solarDayContaining>) {
  const tz = place.timeZone;
  const phase = moonDialModel(now, place).phase;
  const events = lunarEvents(day.solarMidnight, day.nextSolarMidnight, place);
  const next = events.find((e) => e.date > now);
  const rows = [
    `<li class="moon-head"><canvas id="moon-glyph" width="88" height="88" aria-hidden="true"></canvas><span>${phaseName(phase)}</span>` +
      `<span class="time lit">${Math.round(phase.illumination * 100)}% lit</span></li>`,
    ...events.map(
      (e) => `<li class="${e === next ? "next" : e.date <= now ? "past" : ""}"><span>${lunarEventNames[e.event]}</span><span class="time">${clockTime(e.date, tz)}</span></li>`,
    ),
  ];
  const rises = events.some((e) => e.event === "moonrise"), sets = events.some((e) => e.event === "moonset");
  if (!rises || !sets) {
    const note = !rises && !sets ? "No moonrise or moonset today." : !rises ? "No moonrise today." : "No moonset today.";
    rows.push(`<li><span class="note">${note}</span></li>`);
  }
  const eclipse = nextEclipse(now, place, tz);
  if (eclipse) {
    const title = fromEclipse(eclipse, place, tz).title.replace(" eclipse", "").toLowerCase();
    rows.push(`<li><span>Next eclipse: ${title}</span><span class="time">${shortDate(eclipseDate(eclipse), tz)}</span></li>`);
  }
  $("moon").innerHTML = rows.join("");
  const glyph = $<HTMLCanvasElement>("moon-glyph");
  const ctx = glyph.getContext("2d")!;
  drawMoon(ctx, 44, 44, 22, phase, place.latitude < 0, 1);
}

function escape(text: string): string {
  return text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
}

let frame = 0;
const scheduleRender = () => {
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(render);
};

// MARK: Places

const cities: Place[] = [
  { name: "Seattle", latitude: 47.61, longitude: -122.33, timeZone: "America/Los_Angeles" },
  { name: "New York", latitude: 40.71, longitude: -74.01, timeZone: "America/New_York" },
  { name: "Dallas", latitude: 32.78, longitude: -96.8, timeZone: "America/Chicago" },
  { name: "Honolulu", latitude: 21.31, longitude: -157.86, timeZone: "Pacific/Honolulu" },
  { name: "London", latitude: 51.51, longitude: -0.13, timeZone: "Europe/London" },
  { name: "Reykjavík", latitude: 64.15, longitude: -21.94, timeZone: "Atlantic/Reykjavik" },
  { name: "Tromsø", latitude: 69.65, longitude: 18.96, timeZone: "Europe/Oslo" },
  { name: "Nairobi", latitude: -1.29, longitude: 36.82, timeZone: "Africa/Nairobi" },
  { name: "Tokyo", latitude: 35.68, longitude: 139.69, timeZone: "Asia/Tokyo" },
  { name: "Sydney", latitude: -33.87, longitude: 151.21, timeZone: "Australia/Sydney" },
];

function setPlace(place: Place) {
  state.place = place;
  storage.set("place", place);
  dayCache.clear();
  render();
}

function locate() {
  const error = $("place-error");
  if (!("geolocation" in navigator)) {
    error.textContent = "This browser can't share a location. Pick a city or enter coordinates.";
    openPlaceDialog();
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (position) => {
      // Two decimals is about a kilometer: plenty for sun and moon times.
      const round = (x: number) => Math.round(x * 100) / 100;
      setPlace({
        name: "Current location",
        latitude: round(position.coords.latitude),
        longitude: round(position.coords.longitude),
        timeZone: browserTimeZone(),
      });
      if (dialog.open) dialog.close();
    },
    () => {
      error.textContent = "Location isn't available. Pick a city or enter coordinates.";
      openPlaceDialog();
    },
    { enableHighAccuracy: false, maximumAge: 30 * 60_000, timeout: 15_000 },
  );
}

function openPlaceDialog() {
  const place = state.place;
  (form.elements.namedItem("name") as HTMLInputElement).value = place?.name ?? "";
  (form.elements.namedItem("latitude") as HTMLInputElement).value = place ? String(place.latitude) : "";
  (form.elements.namedItem("longitude") as HTMLInputElement).value = place ? String(place.longitude) : "";
  (form.elements.namedItem("timeZone") as HTMLSelectElement).value = place?.timeZone ?? browserTimeZone();
  if (!dialog.open) dialog.showModal();
}

function setUpPlaceDialog() {
  const select = $<HTMLSelectElement>("tz-select");
  const zones = new Set<string>(typeof Intl.supportedValuesOf === "function" ? Intl.supportedValuesOf("timeZone") : []);
  zones.add(browserTimeZone());
  for (const city of cities) zones.add(city.timeZone);
  select.innerHTML = [...zones].sort().map((z) => `<option value="${z}">${z.replaceAll("_", " ")}</option>`).join("");

  $("cities").innerHTML = cities.map((c, i) => `<button type="button" data-city="${i}">${c.name}</button>`).join("");
  $("cities").addEventListener("click", (event) => {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>("[data-city]");
    if (!button) return;
    setPlace(cities[Number(button.dataset.city)]);
    dialog.close();
  });

  form.addEventListener("submit", (event) => {
    const submitter = (event as SubmitEvent).submitter as HTMLButtonElement | null;
    if (submitter?.value !== "save") return;
    const data = new FormData(form);
    const latitude = Number(String(data.get("latitude")).trim());
    const longitude = Number(String(data.get("longitude")).trim());
    if (!isValid(latitude, longitude)) {
      event.preventDefault();
      $("place-error").textContent = "Latitude is -90 to 90 and longitude -180 to 180 (east is positive).";
      return;
    }
    setPlace({
      name: String(data.get("name")).trim() || "Pinned place",
      latitude,
      longitude,
      timeZone: validTimeZone(String(data.get("timeZone"))),
    });
  });
  dialog.addEventListener("close", () => ($("place-error").textContent = ""));
}

// MARK: Wiring

for (const button of document.querySelectorAll<HTMLButtonElement>("[data-theme-choice]")) {
  button.addEventListener("click", () => {
    state.theme = button.dataset.themeChoice as Theme;
    storage.set("theme", state.theme);
    applyTheme();
    render();
  });
}
for (const button of document.querySelectorAll<HTMLButtonElement>("[data-dial-choice]")) {
  button.addEventListener("click", () => {
    state.orientation = button.dataset.dialChoice as Orientation;
    storage.set("orientation", state.orientation);
    render();
  });
}
for (const button of document.querySelectorAll<HTMLButtonElement>("[data-moon-choice]")) {
  button.addEventListener("click", () => {
    state.moonMode = button.dataset.moonChoice as MoonMode;
    storage.set("moonMode", state.moonMode);
    render();
  });
}
document.addEventListener("click", (event) => {
  const action = (event.target as HTMLElement).closest<HTMLElement>("[data-action]")?.dataset.action;
  if (action === "locate") locate();
  if (action === "choose") openPlaceDialog();
});
$("place-button").addEventListener("click", openPlaceDialog);
$("dial-center").addEventListener("click", () => {
  state.display = displays[(displays.indexOf(state.display) + 1) % displays.length];
  displaySelect.value = state.display;
  embers();
  storage.set("display", state.display);
  render();
});
scrubber.addEventListener("input", () => {
  state.scrubMinutes = Number(scrubber.value);
  scheduleRender();
});
nowButton.addEventListener("click", () => {
  state.scrubMinutes = 0;
  render();
});
darkQuery.addEventListener("change", render);
window.addEventListener("resize", scheduleRender);
document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && render());

setUpPlaceDialog();
applyTheme();
render();
loadMoonTexture(`${import.meta.env.BASE_URL}moon.png`).then(render, () => {});
const asset = (name: string) => `${import.meta.env.BASE_URL}${name}`;
loadOrbitTextures(asset("earth-day.jpg"), asset("earth-night.jpg"), asset("moon.png"), asset("starmap.jpg")).then(redrawOrbit, () => {});
loadSunImage(asset("sun.jpg")).then(redrawOrbit, () => {});
loadSunSpots(asset("sun-flat.jpg")).then(render, () => {});
if (!Number.isFinite(frozenNow)) setInterval(render, 15_000);
shimmer();
embers();
