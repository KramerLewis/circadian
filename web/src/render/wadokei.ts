// The wadokei overlay: the twelve zodiac kanji around the outside of the sun ring, each
// at the middle of its temporal hour (so they bunch up in short hours and spread out in
// long ones, as on an Edo clock), and the current hour's kanji large in the middle.
//
// Each kanji is a hole cut through the dial: idle ones shallow and dark, the active one
// deep, with molten rock inside lighting its walls and glowing out of the opening. Its own
// canvas, so the molten surface can move without redrawing the dial.

import { dialGeometry } from "./dial";

export const wadokeiFont = `"SunClock Wadokei", "Hiragino Mincho ProN", "Yu Mincho", serif`;

export type KanjiStyle = "molten" | "plain" | "silver" | "gold";

export const kanjiStyles: { id: KanjiStyle; title: string }[] = [
  { id: "molten", title: "Molten" },
  { id: "plain", title: "Plain (black or white)" },
  { id: "silver", title: "Silver" },
  { id: "gold", title: "Gold" },
];

export interface WadokeiScene {
  style: KanjiStyle;
  hours: { kanji: string; angle: number; active: boolean }[];
  /** Degrees the dial is turned (now at top). */
  rotation: number;
  dark: boolean;
}

export function drawWadokei(canvas: HTMLCanvasElement, scene: WadokeiScene, time: number | undefined) {
  const side = canvas.clientWidth;
  const scale = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(side * scale)) canvas.width = canvas.height = Math.round(side * scale);
  const ctx = canvas.getContext("2d")!;
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.clearRect(0, 0, side, side);
  const g = dialGeometry(side);
  const cx = side / 2, cy = side / 2;
  const radius = g.outer + 18;
  const size = Math.max(13, Math.min(20, side * 0.045));
  for (const hour of scene.hours) {
    const t = ((hour.angle + scene.rotation) * Math.PI) / 180;
    const x = cx + radius * Math.sin(t), y = cy - radius * Math.cos(t);
    if (scene.style !== "molten") flat(ctx, hour.kanji, x, y, hour.active ? size * 1.25 : size, scene.style, hour.active, time, scene.dark);
    else if (hour.active) hole(ctx, hour.kanji, x, y, size * 1.25, time, scale, true, scene.dark);
    else idleHole(ctx, hour.kanji, x, y, size, scale, scene.dark);
  }
  const active = scene.hours.find((h) => h.active);
  if (!active) return;
  const [ax, ay, as] = [cx, cy - g.moonInner * 0.12, g.moonInner * 0.95];
  if (scene.style === "molten") hole(ctx, active.kanji, ax, ay, as, time, scale, true, scene.dark);
  else flat(ctx, active.kanji, ax, ay, as, scene.style, true, time, scene.dark);
}

/**
 * Plain, silver and gold kanji: printed on the dial rather than cut through it. Idle
 * ones are quiet; the active one is emboldened (a stroke of its own color) and glows,
 * and silver and gold catch a slow highlight that sweeps across them.
 */
function flat(
  ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number,
  style: Exclude<KanjiStyle, "molten">, active: boolean, time: number | undefined, dark: boolean,
) {
  ctx.save();
  ctx.font = `${size}px ${wadokeiFont}`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.lineJoin = "round";
  let fill: string | CanvasGradient;
  let glow: string;
  if (style === "plain") {
    fill = dark ? "rgb(245, 245, 248)" : "rgb(18, 18, 22)";
    glow = dark ? "rgba(255, 255, 255, 0.75)" : "rgba(0, 0, 0, 0.35)";
  } else {
    // A metal: dark, bright and dark again from top to bottom, with a highlight band
    // that sweeps across (every four seconds) when active.
    // Deeper tones on light backgrounds, so the metal still reads.
    const tones = style === "gold"
      ? dark
        ? ["rgb(140, 92, 20)", "rgb(255, 226, 140)", "rgb(196, 140, 40)", "rgb(255, 246, 200)"]
        : ["rgb(110, 70, 8)", "rgb(206, 150, 40)", "rgb(140, 92, 16)", "rgb(255, 232, 150)"]
      : dark
        ? ["rgb(110, 114, 124)", "rgb(238, 240, 246)", "rgb(150, 154, 164)", "rgb(255, 255, 255)"]
        : ["rgb(62, 66, 76)", "rgb(150, 156, 170)", "rgb(88, 92, 104)", "rgb(230, 236, 248)"];
    const g = ctx.createLinearGradient(x - size / 2, y - size / 2, x + size / 2, y + size / 2);
    g.addColorStop(0, tones[0]);
    g.addColorStop(0.45, tones[1]);
    g.addColorStop(1, tones[2]);
    if (active && time !== undefined) {
      const t = (time / 4) % 1;
      const at = (k: number) => Math.min(1, Math.max(0, k));
      g.addColorStop(at(t - 0.08), tones[1]);
      g.addColorStop(at(t), tones[3]);
      g.addColorStop(at(t + 0.08), tones[1]);
    }
    fill = g;
    glow = style === "gold"
      ? dark ? "rgba(255, 200, 80, 0.8)" : "rgba(200, 140, 20, 0.55)"
      : dark ? "rgba(220, 232, 255, 0.8)" : "rgba(70, 90, 130, 0.45)";
  }
  ctx.globalAlpha = active ? 1 : style === "plain" ? 0.45 : 0.6;
  if (active) {
    ctx.shadowColor = glow;
    ctx.shadowBlur = size * 0.35;
    // Embolden: stroke the glyph in its own fill.
    ctx.strokeStyle = fill;
    ctx.lineWidth = Math.max(1, size * 0.045);
    ctx.strokeText(text, x, y);
  }
  ctx.fillStyle = fill;
  ctx.fillText(text, x, y);
  ctx.restore();
}

/**
 * Each kanji is a hole cut through the dial. Looking in, you see its inner walls (the
 * band left where the floor, set back by `depth`, no longer covers the opening), the floor,
 * an inner shadow where walls meet floor, a dark lip along the top edge and a lit lip
 * along the bottom. Idle holes are shallow and dark; the active one is deep, with molten
 * rock on the floor lighting the walls and glowing out of the opening.
 */
function hole(
  ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number,
  time: number | undefined, scale: number, molten: boolean, dark: boolean,
) {
  const box = Math.ceil(size * 1.4);
  const px = Math.ceil(box * scale);
  const depth = Math.max(1.2, size * (molten ? 0.045 : 0.035)) * scale;
  const canvas = () => {
    const c = document.createElement("canvas");
    c.width = c.height = px;
    return [c, c.getContext("2d")!] as const;
  };
  // The opening, as a mask.
  const [mask, m] = canvas();
  m.font = `${size * scale}px ${wadokeiFont}`;
  m.textAlign = "center";
  m.textBaseline = "middle";
  m.fillStyle = "white";
  m.fillText(text, px / 2, px / 2);
  // The floor: the opening moved back by the depth, seen through the opening.
  const [floorMask, f] = canvas();
  f.drawImage(mask, 0, depth);
  f.globalCompositeOperation = "destination-in";
  f.drawImage(mask, 0, 0);

  const [hollow, h] = canvas();
  // Walls: dark at the surface; in a molten hole, lit orange near the floor.
  const wall = h.createLinearGradient(0, 0, 0, px);
  if (molten) {
    wall.addColorStop(0, "rgb(70, 18, 6)");
    wall.addColorStop(1, "rgb(230, 96, 30)");
  } else {
    wall.addColorStop(0, dark ? "rgb(22, 20, 19)" : "rgb(40, 32, 28)");
    wall.addColorStop(1, dark ? "rgb(58, 52, 48)" : "rgb(90, 76, 66)");
  }
  h.drawImage(mask, 0, 0);
  h.globalCompositeOperation = "source-in";
  h.fillStyle = wall;
  h.fillRect(0, 0, px, px);
  // The floor on top of the walls.
  const [floor, fl] = canvas();
  if (molten) paintMolten(fl, px, time ?? 0);
  else {
    fl.fillStyle = dark ? "rgb(40, 36, 33)" : "rgb(62, 52, 46)";
    fl.fillRect(0, 0, px, px);
  }
  fl.globalCompositeOperation = "destination-in";
  fl.drawImage(floorMask, 0, 0);
  h.globalCompositeOperation = "source-over";
  h.drawImage(floor, 0, 0);
  // Inner shadow where walls meet the floor: the shadow of everything outside the
  // floor, kept inside the hole (drawn far off-canvas so only its shadow lands).
  const [outside, o] = canvas();
  o.fillRect(0, 0, px, px);
  o.globalCompositeOperation = "destination-out";
  o.drawImage(floorMask, 0, 0);
  h.globalCompositeOperation = "source-atop";
  h.shadowColor = molten ? "rgba(60, 10, 0, 0.6)" : "rgba(0, 0, 0, 0.7)";
  h.shadowBlur = size * scale * (molten ? 0.05 : 0.04);
  h.shadowOffsetX = 4 * px;
  h.drawImage(outside, -4 * px, 0);

  const left = x - box / 2, top = y - box / 2;
  ctx.save();
  // A dark lip along the top edges and a lit lip along the bottom edges of the opening.
  ctx.globalAlpha = dark ? 0.9 : 0.5;
  tinted(ctx, mask, left, top - 1, box, "rgb(0, 0, 0)");
  ctx.globalAlpha = 1;
  tinted(ctx, mask, left, top + 1, box, molten ? "rgba(255, 196, 120, 0.75)" : dark ? "rgba(255, 240, 225, 0.45)" : "rgba(255, 255, 255, 0.9)");
  if (molten) {
    // Heat glowing out of the opening, flickering.
    const s = time ?? 0;
    const flicker = 1 + 0.05 * Math.sin(s * 2.3) * Math.sin(s * 1.3 + 1);
    ctx.shadowColor = `rgba(255, 130, 40, ${Math.min(1, 0.95 * flicker)})`;
    ctx.shadowBlur = size * 0.55 * flicker;
  }
  ctx.drawImage(hollow, left, top, box, box);
  ctx.restore();
}

/** Molten rock: a hot core, drifting dark crust, and bright cracks between. */
function paintMolten(c: CanvasRenderingContext2D, px: number, s: number) {
  const core = c.createRadialGradient(px / 2, px * 0.55, 0, px / 2, px / 2, px * 0.6);
  core.addColorStop(0, "rgb(255, 238, 170)");
  core.addColorStop(0.4, "rgb(255, 150, 40)");
  core.addColorStop(1, "rgb(196, 54, 12)");
  c.fillStyle = core;
  c.fillRect(0, 0, px, px);
  for (let k = 0; k < 7; k++) {
    const cx = px * (0.5 + 0.38 * Math.sin(s * (0.11 + k * 0.023) + k * 2.1));
    const cy = px * (0.5 + 0.38 * Math.cos(s * (0.09 + k * 0.019) + k * 1.3));
    const r = px * (0.12 + 0.015 * Math.sin(s * 0.4 + k));
    const crust = c.createRadialGradient(cx, cy, 0, cx, cy, r);
    crust.addColorStop(0, "rgba(70, 14, 4, 0.75)");
    crust.addColorStop(0.7, "rgba(110, 24, 6, 0.4)");
    crust.addColorStop(1, "rgba(110, 24, 6, 0)");
    c.fillStyle = crust;
    c.fillRect(0, 0, px, px);
  }
  for (let k = 0; k < 5; k++) {
    const cx = px * (0.5 + 0.34 * Math.sin(s * (0.37 + k * 0.05) + k * 0.9));
    const cy = px * (0.5 + 0.34 * Math.cos(s * (0.31 + k * 0.04) + k * 2.6));
    const r = px * (0.09 + 0.01 * Math.sin(s * 0.8 + k));
    const vent = c.createRadialGradient(cx, cy, 0, cx, cy, r);
    vent.addColorStop(0, `rgba(255, 252, 220, ${0.65 + 0.1 * Math.sin(s * 1.2 + k)})`);
    vent.addColorStop(1, "rgba(255, 220, 140, 0)");
    c.fillStyle = vent;
    c.fillRect(0, 0, px, px);
  }
}

/** Draw a mask filled with one color. */
function tinted(ctx: CanvasRenderingContext2D, mask: HTMLCanvasElement, x: number, y: number, box: number, color: string) {
  const c = document.createElement("canvas");
  c.width = mask.width;
  c.height = mask.height;
  const t = c.getContext("2d")!;
  t.drawImage(mask, 0, 0);
  t.globalCompositeOperation = "source-in";
  t.fillStyle = color;
  t.fillRect(0, 0, c.width, c.height);
  ctx.drawImage(c, x, y, box, box);
}

/** Idle holes don't change, so each is rendered once (cleared when the font arrives). */
const idleCache = new Map<string, HTMLCanvasElement>();

export function clearWadokeiCache() {
  idleCache.clear();
}

function idleHole(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number, scale: number, dark: boolean) {
  const box = Math.ceil(size * 1.6);
  const key = `${text}|${size.toFixed(1)}|${scale}|${dark}`;
  let c = idleCache.get(key);
  if (!c) {
    c = document.createElement("canvas");
    c.width = c.height = Math.ceil(box * scale);
    const k = c.getContext("2d")!;
    k.scale(scale, scale);
    hole(k, text, box / 2, box / 2, size, undefined, scale, false, dark);
    if (idleCache.size > 64) idleCache.clear();
    idleCache.set(key, c);
  }
  ctx.drawImage(c, x - box / 2, y - box / 2, box, box);
}
