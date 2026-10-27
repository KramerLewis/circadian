// The wadokei overlay: the twelve zodiac kanji around the outside of the sun ring, each
// at the middle of its temporal hour (so they bunch up in short hours and spread out in
// long ones, as on an Edo clock), and the current hour's kanji large in the middle.
//
// Inactive kanji look cut into the dial; the active one glows as if lit by embers from
// inside: a hot core shading to deep red at the edges, slowly shifting hot spots, and a
// soft flickering glow. Its own canvas, so the flicker animates without the dial.

import { dialGeometry } from "./dial";

export const wadokeiFont = `"SunClock Wadokei", "Hiragino Mincho ProN", "Yu Mincho", serif`;

export interface WadokeiScene {
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
    if (hour.active) ember(ctx, hour.kanji, x, y, size * 1.25, time, scale);
    else engraved(ctx, hour.kanji, x, y, size, scene.dark);
  }
  const active = scene.hours.find((h) => h.active);
  if (active) ember(ctx, active.kanji, cx, cy - g.moonInner * 0.12, g.moonInner * 0.95, time, scale);
}

/** Cut into the dial: a dark recess with a faint lit lower edge. */
function engraved(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number, dark: boolean) {
  ctx.save();
  ctx.font = `${size}px ${wadokeiFont}`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  // A shadow above and a lit lip below make it read as carved in.
  ctx.fillStyle = dark ? "rgba(0, 0, 0, 0.8)" : "rgba(40, 30, 24, 0.35)";
  ctx.fillText(text, x, y - 0.8);
  ctx.fillStyle = dark ? "rgba(255, 238, 220, 0.22)" : "rgba(255, 255, 255, 0.85)";
  ctx.fillText(text, x, y + 0.8);
  ctx.fillStyle = dark ? "rgba(200, 186, 172, 0.55)" : "rgba(70, 56, 46, 0.6)";
  ctx.fillText(text, x, y);
  ctx.restore();
}

/**
 * The kanji filled with ember light: rendered into a small offscreen canvas as a mask,
 * painted with a hot gradient and moving hot spots, then drawn with a flickering glow
 * and a dark rim, so it reads as a cutout with fire behind it.
 */
function ember(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number, time: number | undefined, scale: number) {
  const box = Math.ceil(size * 1.4);
  const px = Math.ceil(box * scale);
  const off = document.createElement("canvas");
  off.width = off.height = px;
  const o = off.getContext("2d")!;
  o.scale(scale, scale);
  o.font = `${size}px ${wadokeiFont}`;
  o.textAlign = "center";
  o.textBaseline = "middle";
  o.fillStyle = "white";
  o.fillText(text, box / 2, box / 2);
  // Paint the glyph: a hot core, deepening toward the edges.
  o.globalCompositeOperation = "source-in";
  const s = time ?? 0;
  const core = o.createRadialGradient(box / 2, box * 0.55, 0, box / 2, box / 2, box * 0.62);
  core.addColorStop(0, "rgb(255, 244, 196)");
  core.addColorStop(0.35, "rgb(255, 176, 64)");
  core.addColorStop(0.7, "rgb(232, 84, 24)");
  core.addColorStop(1, "rgb(120, 22, 6)");
  o.fillStyle = core;
  o.fillRect(0, 0, box, box);
  // Hot spots that drift and pulse, like coals.
  o.globalCompositeOperation = "source-atop";
  for (let k = 0; k < 5; k++) {
    const hx = box * (0.5 + 0.32 * Math.sin(s * (0.31 + k * 0.07) + k * 1.7));
    const hy = box * (0.5 + 0.32 * Math.cos(s * (0.27 + k * 0.05) + k * 2.3));
    const r = box * (0.16 + 0.06 * Math.sin(s * 1.3 + k));
    const spot = o.createRadialGradient(hx, hy, 0, hx, hy, r);
    const a = 0.35 + 0.25 * Math.sin(s * 2.1 + k * 1.1);
    spot.addColorStop(0, `rgba(255, 250, 220, ${a})`);
    spot.addColorStop(1, "rgba(255, 200, 120, 0)");
    o.fillStyle = spot;
    o.fillRect(0, 0, box, box);
  }
  const flicker = 1 + 0.18 * Math.sin(s * 7.3) * Math.sin(s * 3.1 + 1);
  ctx.save();
  // A dark rim first: the edge of the cutout.
  ctx.font = `${size}px ${wadokeiFont}`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.lineJoin = "round";
  ctx.lineWidth = Math.max(1.5, size * 0.05);
  ctx.strokeStyle = "rgba(30, 8, 2, 0.85)";
  ctx.strokeText(text, x, y);
  // Then the lit glyph with its glow.
  ctx.shadowColor = `rgba(255, 110, 30, ${0.85 * flicker})`;
  ctx.shadowBlur = size * 0.35 * flicker;
  ctx.drawImage(off, x - box / 2, y - box / 2, box, box);
  ctx.shadowBlur = size * 0.12;
  ctx.shadowColor = "rgba(255, 200, 90, 0.9)";
  ctx.drawImage(off, x - box / 2, y - box / 2, box, box);
  ctx.restore();
}
