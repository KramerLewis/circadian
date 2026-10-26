// Draws the 24-hour solar dial on a canvas: the sky ring (solar noon at the top), the
// moon ring inside it on the same timeline, hour ticks, event markers, the hand,
// the glowing sun, and the marks for special sky days. A port of the iOS dial
// (SolarDialView + SkyRingRenderer).

import {
  type DialModel, type MoonDialModel, type RGB, angleForSolarHour, dialAltitude, moonAltitudeAt, moonRingColor, skyColor, sunColor,
} from "../core/dial";
import { type SolarEvent, altitude } from "../core/solar";
import type { SpecialStyle } from "../core/specialDay";
import type { Phase } from "../core/lunar";
import { moonImage } from "./moon";
import { sunImage } from "./sun";

export interface DialColors {
  primary: string;
  secondary: string;
}

export interface DialScene {
  model: DialModel;
  moon: MoonDialModel;
  dark: boolean;
  colors: DialColors;
  special?: SpecialStyle;
  /** Umbral coverage during a lunar eclipse. */
  eclipseShadow: number;
  /** The moon's offset and size relative to the sun during a solar eclipse. */
  solarEclipse?: { offset: number; moonScale: number };
  /** Clock text for an event marker. */
  label: (date: number) => string;
  /** "noon": solar noon fixed at the top; "now": the dial turns so now is at the top. */
  orientation: "noon" | "now";
  /** "clock": the moon ring on the sun's timeline; "sky": the moon where it is in the sky. */
  moonMode: "clock" | "sky";
  /** Half the size of the center readout, to keep hour numbers out from under it. */
  readout: { halfWidth: number; halfHeight: number };
}

interface Ring {
  cx: number;
  cy: number;
  inner: number;
  outer: number;
  /** Degrees the whole dial is turned clockwise. */
  rotation: number;
}

const dialFont = `ui-rounded, "SF Pro Rounded", system-ui, -apple-system, "Segoe UI", sans-serif`;
const labeledEvents = new Set<SolarEvent>(["sunrise", "sunset", "solarNoon", "solarMidnight"]);

/** Where the readout in the middle can go without covering the hour labels. */
export function dialGeometry(side: number) {
  // Room outside the ring for the clock labels at the sides.
  const outer = side / 2 - 64;
  const inner = outer * 0.8;
  const moonOuter = inner - 5;
  const moonInner = moonOuter - outer * 0.1;
  return { outer, inner, moonOuter, moonInner, centerWidth: moonInner * 1.3 };
}

export function drawDial(canvas: HTMLCanvasElement, scene: DialScene): void {
  const side = canvas.clientWidth;
  const scale = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(side * scale)) {
    canvas.width = canvas.height = Math.round(side * scale);
  }
  const ctx = canvas.getContext("2d")!;
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.clearRect(0, 0, side, side);
  const g = dialGeometry(side);
  const rotation = scene.orientation === "now" ? -scene.model.nowAngle : 0;
  const sunRing: Ring = { cx: side / 2, cy: side / 2, inner: g.inner, outer: g.outer, rotation };
  const moonRing: Ring = { cx: side / 2, cy: side / 2, inner: g.moonInner, outer: g.moonOuter, rotation };

  if (scene.special === "solstice") drawSolsticeHalo(ctx, sunRing);
  drawSky(ctx, sunRing, scene.model, scene.dark);
  drawMoonRing(ctx, moonRing, scene, scale);
  if (scene.special === "equinox") drawEquinox(ctx, sunRing);
  if (scene.special === "newMoon") drawStars(ctx, sunRing, g.moonInner, scene.dark);
  drawHourTicks(ctx, sunRing, g.moonInner, scene.colors, scene.readout);
  drawMarkers(ctx, sunRing, scene);
  drawHand(ctx, sunRing, scene, scale);
}

// MARK: Rings

function point(r: Ring, radius: number, degrees: number): [number, number] {
  const t = ((degrees + r.rotation) * Math.PI) / 180;
  return [r.cx + radius * Math.sin(t), r.cy - radius * Math.cos(t)];
}

function ringPath(r: Ring): Path2D {
  const path = new Path2D();
  path.arc(r.cx, r.cy, r.outer, 0, Math.PI * 2);
  path.moveTo(r.cx + r.inner, r.cy);
  path.arc(r.cx, r.cy, r.inner, 0, Math.PI * 2, true);
  return path;
}

const css = (c: RGB, alpha = 1) =>
  `rgba(${Math.round(Math.min(c[0], 1) * 255)}, ${Math.round(Math.min(c[1], 1) * 255)}, ${Math.round(Math.min(c[2], 1) * 255)}, ${alpha})`;

/** A conic gradient sampled every degree, starting at the top like dial angles. */
function conic(ctx: CanvasRenderingContext2D, r: Ring, color: (degree: number) => RGB): CanvasGradient {
  const gradient = ctx.createConicGradient(((r.rotation - 90) * Math.PI) / 180, r.cx, r.cy);
  for (let degree = 0; degree <= 360; degree += 2) gradient.addColorStop(degree / 360, css(color(degree)));
  return gradient;
}

function drawSky(ctx: CanvasRenderingContext2D, r: Ring, model: DialModel, dark: boolean) {
  ctx.fillStyle = conic(ctx, r, (d) => skyColor(dialAltitude(model, d), dark));
  ctx.fill(ringPath(r), "evenodd");
}

function drawMoonRing(ctx: CanvasRenderingContext2D, r: Ring, scene: DialScene, scale: number) {
  const { moon, special } = scene;
  // Full moons light up the ring; a supermoon most of all.
  const boost = special === "supermoon" ? 1.3 : special === "fullMoon" || special === "blueMoon" ? 1.15 : 1;
  const sky = scene.moonMode === "sky";
  // In the sky view the ring is directions round the sky (the moon's hour angle), so the
  // part above the horizon is centered on the top, like the sun's.
  const altitudeAt = (d: number) => (sky ? altitude(d, moon.latitude, moon.sky.declination) : moonAltitudeAt(moon, d));
  ctx.fillStyle = conic(ctx, r, (d) =>
    moonRingColor(altitudeAt(d), moon.riseSetAltitude, Math.min(moon.phase.illumination * boost, 1.3), scene.dark),
  );
  ctx.fill(ringPath(r), "evenodd");
  ctx.strokeStyle = scene.colors.secondary;
  ctx.lineWidth = 1;
  // In the sky view the ticks are where the moon crosses the horizon; they don't line
  // up with the hours (those follow the sun), so the page prints the times below.
  const ticks = sky
    ? moon.sky.riseSetAngle === undefined ? [] : [-moon.sky.riseSetAngle, moon.sky.riseSetAngle]
    : moon.horizonMarkers.map((m) => m.angle);
  for (const angle of ticks) {
    ctx.beginPath();
    ctx.moveTo(...point(r, r.inner, angle));
    ctx.lineTo(...point(r, r.outer, angle));
    ctx.stroke();
  }
  const thickness = r.outer - r.inner;
  const glow = special === "supermoon" ? 2.4 : special === "fullMoon" || special === "blueMoon" ? 1.8 : 1;
  const [x, y] = point(r, (r.inner + r.outer) / 2, sky ? moon.sky.nowAngle : moon.nowAngle);
  drawMoon(ctx, x, y, thickness * (special === "supermoon" ? 0.95 : 0.75), moon.phase, moon.latitude < 0, scale, {
    glowScale: glow,
    blueGlow: special === "blueMoon",
    shadow: scene.eclipseShadow,
  });
}

/** The moon in its phase with a soft glow that grows as it fills. */
export function drawMoon(
  ctx: CanvasRenderingContext2D, x: number, y: number, radius: number, phase: Phase, southern: boolean, scale: number,
  options: { glowScale?: number; blueGlow?: boolean; shadow?: number } = {},
) {
  const glowScale = options.glowScale ?? 1, shadow = options.shadow ?? 0;
  const k = Math.min(phase.illumination * glowScale, 2);
  const glow = radius * (1.9 + 0.5 * (glowScale - 1));
  const color: RGB = shadow > 0.3 ? [0.85, 0.3, 0.2] : options.blueGlow ? [0.45, 0.62, 1.0] : [0.8, 0.84, 0.97];
  const gradient = ctx.createRadialGradient(x, y, radius * 0.95, x, y, glow);
  gradient.addColorStop(0, css(color, 0.1 + 0.35 * k));
  gradient.addColorStop(1, css(color, 0));
  ctx.fillStyle = gradient;
  ctx.beginPath();
  ctx.arc(x, y, glow, 0, Math.PI * 2);
  ctx.fill();
  ctx.drawImage(moonImage(phase, southern, radius * 2 * scale, shadow), x - radius, y - radius, radius * 2, radius * 2);
}

// MARK: Ticks, markers, hand

function drawHourTicks(
  ctx: CanvasRenderingContext2D, r: Ring, base: number, colors: DialColors, readout: { halfWidth: number; halfHeight: number },
) {
  ctx.strokeStyle = colors.secondary;
  ctx.fillStyle = colors.secondary;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  for (let hour = 0; hour < 24; hour++) {
    const angle = angleForSolarHour(hour);
    const major = hour % 6 === 0;
    ctx.lineWidth = major ? 2 : 1;
    ctx.beginPath();
    ctx.moveTo(...point(r, base - 2, angle));
    ctx.lineTo(...point(r, base - (major ? 9 : 5), angle));
    ctx.stroke();
    // Skip a number that the turning dial would put under the center readout.
    const [x, y] = point(r, base - 17, angle);
    const underReadout = Math.abs(x - r.cx) < readout.halfWidth + 7 && Math.abs(y - r.cy) < readout.halfHeight + 6;
    if (hour % 3 === 0 && !underReadout) {
      ctx.font = `${major ? 600 : 400} 11px ${dialFont}`;
      ctx.fillText(String(hour), x, y);
    }
  }
}

function drawMarkers(ctx: CanvasRenderingContext2D, r: Ring, scene: DialScene) {
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = `11px ${dialFont}`;
  for (const marker of scene.model.markers) {
    if (labeledEvents.has(marker.event)) {
      const [x, y] = point(r, r.outer + 6, marker.angle);
      ctx.fillStyle = scene.colors.primary;
      ctx.beginPath();
      ctx.arc(x, y, 3, 0, Math.PI * 2);
      ctx.fill();
      // Anchor the label on its inner edge, so it grows away from the ring at any angle.
      const side = Math.sin(((marker.angle + r.rotation) * Math.PI) / 180);
      ctx.textAlign = side > 0.35 ? "left" : side < -0.35 ? "right" : "center";
      ctx.fillStyle = scene.colors.secondary;
      ctx.fillText(scene.label(marker.date), ...point(r, r.outer + (Math.abs(side) > 0.35 ? 14 : 20), marker.angle));
    } else {
      ctx.strokeStyle = scene.colors.secondary;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(...point(r, r.outer + 2, marker.angle));
      ctx.lineTo(...point(r, r.outer + 8, marker.angle));
      ctx.stroke();
    }
  }
}

function drawHand(ctx: CanvasRenderingContext2D, r: Ring, scene: DialScene, scale: number) {
  const angle = scene.model.nowAngle;
  ctx.save();
  ctx.globalAlpha = 0.7;
  ctx.strokeStyle = scene.colors.primary;
  ctx.lineWidth = 1.5;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(...point(r, r.inner - 4, angle));
  ctx.lineTo(...point(r, r.outer + 4, angle));
  ctx.stroke();
  ctx.restore();
  drawSun(ctx, r, angle, dialAltitude(scene.model, angle), scale, scene.solarEclipse);
}

/** The sun inside a two-layer corona tinted for its altitude, clipped to the ring. */
function drawSun(
  ctx: CanvasRenderingContext2D, r: Ring, angle: number, altitude: number, scale: number,
  eclipse?: { offset: number; moonScale: number },
) {
  const strength = altitude >= -0.833 ? 1 : Math.max(0.3, 1 + (altitude + 0.833) / 25);
  const glow = sunColor(altitude).glow;
  const [x, y] = point(r, (r.inner + r.outer) / 2, angle);
  const radius = (r.outer - r.inner) * 0.3;
  ctx.save();
  ctx.clip(ringPath(r), "evenodd");
  for (const [reach, opacity] of [[radius * 4.6, 0.35], [radius * 2.0, 0.6]]) {
    const gradient = ctx.createRadialGradient(x, y, radius * 0.9, x, y, reach);
    gradient.addColorStop(0, css(glow, opacity * strength));
    gradient.addColorStop(1, css(glow, 0));
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(x, y, reach, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.drawImage(sunImage(altitude, radius * 2 * scale), x - radius, y - radius, radius * 2, radius * 2);
  if (eclipse && Math.abs(eclipse.offset) < 1 + eclipse.moonScale) {
    // The moon's silhouette crossing the sun.
    if (Math.abs(eclipse.offset) < eclipse.moonScale - 1) {
      // Totality: the corona flares around the black disc.
      const corona = ctx.createRadialGradient(x, y, radius, x, y, radius * 1.9);
      corona.addColorStop(0, "rgba(255, 255, 255, 0.85)");
      corona.addColorStop(1, "rgba(255, 255, 255, 0)");
      ctx.fillStyle = corona;
      ctx.beginPath();
      ctx.arc(x, y, radius * 1.9, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = "rgb(15, 15, 23)";
    ctx.beginPath();
    ctx.arc(x + radius * eclipse.offset, y, radius * eclipse.moonScale, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

// MARK: Special days

/** A golden halo around the sun ring, strongest at the top (solar noon). */
function drawSolsticeHalo(ctx: CanvasRenderingContext2D, r: Ring) {
  const thickness = r.outer - r.inner;
  const gradient = ctx.createConicGradient(((r.rotation - 90) * Math.PI) / 180, r.cx, r.cy);
  const stops: [number, number, number][] = [[0, 0.9, 0], [0.25, 0.35, 1], [0.5, 0.15, 0], [0.75, 0.35, 1], [1, 0.9, 0]];
  for (const [at, alpha, yellow] of stops) {
    gradient.addColorStop(at, yellow ? `rgba(255, 214, 10, ${alpha})` : `rgba(255, 149, 0, ${alpha})`);
  }
  ctx.save();
  ctx.strokeStyle = gradient;
  // Layered strokes stand in for a blur, which not every browser's canvas supports.
  for (let i = 0; i < 8; i++) {
    ctx.globalAlpha = 0.16;
    ctx.lineWidth = thickness * (0.2 + i * 0.12);
    ctx.beginPath();
    ctx.arc(r.cx, r.cy, r.outer + 3, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();
}

/** The horizon: sunrise and sunset sit on the 6 and 18 marks today. */
function drawEquinox(ctx: CanvasRenderingContext2D, r: Ring) {
  const [lx, ly] = point(r, r.outer + 14, -90), [rx, ry] = point(r, r.outer + 14, 90);
  ctx.save();
  const gradient = ctx.createLinearGradient(lx, ly, rx, ry);
  gradient.addColorStop(0, "rgb(255, 214, 140)");
  gradient.addColorStop(0.5, "rgba(255, 214, 140, 0.15)");
  gradient.addColorStop(1, "rgb(255, 214, 140)");
  ctx.shadowColor = "rgba(255, 214, 140, 0.9)";
  ctx.shadowBlur = 8;
  ctx.strokeStyle = gradient;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(lx, ly);
  ctx.lineTo(rx, ry);
  ctx.stroke();
  ctx.fillStyle = "rgb(255, 214, 140)";
  for (const [x, y] of [[lx, ly], [rx, ry]]) {
    ctx.beginPath();
    ctx.arc(x, y, 5, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

/** A sprinkle of stars: the darkest skies of the month. */
function drawStars(ctx: CanvasRenderingContext2D, r: Ring, innerRadius: number, dark: boolean) {
  let seed = 0x5eed5eed;
  const random = () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
  const color: RGB = dark ? [0.88, 0.9, 1] : [0.32, 0.36, 0.62];
  for (let i = 0; i < 70; i++) {
    const angle = random() * 360;
    const distance = Math.sqrt(random()) * innerRadius * 0.92;
    const [x, y] = point(r, distance, angle);
    const size = 0.6 + random() * 1.4;
    const alpha = 0.35 + 0.6 * random();
    // Keep the center readout clear.
    if (Math.abs(y - r.cy) < innerRadius * 0.28 && Math.abs(x - r.cx) < innerRadius * 0.75) continue;
    ctx.fillStyle = css(color, alpha);
    ctx.beginPath();
    ctx.arc(x, y, size, 0, Math.PI * 2);
    ctx.fill();
  }
}
