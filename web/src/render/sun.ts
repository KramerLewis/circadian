// The sun's disc for its altitude: limb darkening (stronger in blue, so the edge is
// warmer), faint granulation, and a center brighter than any sky until sunset.
// A port of ios/Shared/SunRenderer.swift. Cached per half degree and size.
//
// With NASA SDO's flattened HMI intensitygram loaded (public/sun-flat.jpg, refreshed by
// the NASA assets workflow), the disc also carries that day's real sunspots.

import { sunColor } from "../core/dial";

const cache = new Map<string, HTMLCanvasElement>();
let spots: { size: number; values: Float32Array } | undefined;

/** Loads the sunspot map: gray, the disc filling the square; values relative to the median. */
export async function loadSunSpots(url: string): Promise<void> {
  const image = new Image();
  image.src = url;
  await image.decode();
  const size = Math.min(image.width, image.height);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(image, 0, 0, size, size);
  const data = ctx.getImageData(0, 0, size, size).data;
  const values = new Float32Array(size * size);
  const inside: number[] = [];
  for (let i = 0; i < values.length; i++) {
    values[i] = data[i * 4];
    const x = (i % size) / size - 0.5, y = Math.floor(i / size) / size - 0.5;
    if (x * x + y * y < 0.16 && i % 7 === 0) inside.push(values[i]);
  }
  inside.sort((a, b) => a - b);
  const median = inside[Math.floor(inside.length / 2)] || 1;
  for (let i = 0; i < values.length; i++) values[i] = Math.min(1.05, values[i] / median);
  spots = { size, values };
  cache.clear();
}

/** Brightness relative to the quiet sun at disc coordinates (-1...1, y up): below 1 in spots. */
function spot(x: number, y: number): number {
  if (!spots) return 1;
  const px = Math.min(spots.size - 1, Math.max(0, Math.floor(((x + 1) / 2) * spots.size)));
  const py = Math.min(spots.size - 1, Math.max(0, Math.floor(((1 - y) / 2) * spots.size)));
  return Math.max(0.25, spots.values[py * spots.size + px]);
}

export function sunImage(altitude: number, pixels: number): HTMLCanvasElement {
  const halfDegrees = Math.round(Math.min(Math.max(altitude, -20), 90) * 2);
  const n = Math.max(Math.ceil(pixels), 8);
  const key = `${halfDegrees}|${n}|${!!spots}`;
  let canvas = cache.get(key);
  if (!canvas) {
    canvas = render(halfDegrees / 2, n);
    if (cache.size > 32) cache.clear();
    cache.set(key, canvas);
  }
  return canvas;
}

function render(altitude: number, n: number): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = n;
  const context = canvas.getContext("2d")!;
  const image = context.createImageData(n, n);
  const out = image.data;
  const core = sunColor(altitude).core;
  const strength = altitude >= -0.833 ? 1 : Math.max(0.3, 1 + (altitude + 0.833) / 25);
  // How much the center washes out toward pale yellow; none once the sun is down.
  const wash = 0.55 * Math.min(Math.max((altitude + 2) / 3, 0), 1);
  const limb = [0.28, 0.4, 0.55];
  const hotValues = [1.0, 0.97, 0.86];
  const half = n / 2;
  for (let row = 0; row < n; row++) {
    for (let col = 0; col < n; col++) {
      const x = (col + 0.5 - half) / half;
      const y = (half - row - 0.5) / half;
      const d = Math.hypot(x, y);
      const alpha = Math.min(Math.max((1 - d) * half, 0), 1);
      if (alpha <= 0) continue;
      const mu = Math.sqrt(Math.max(1 - d * d, 0));
      const hot = Math.pow(Math.min(mu * 1.2, 1), 1.5) * wash;
      // Real sunspots where the map has them, plus a faint granulation.
      const texture = (1 + 0.025 * granulation(x, y) * mu) * (d < 0.97 ? spot(x, y) : 1);
      const i = (row * n + col) * 4;
      for (let c = 0; c < 3; c++) {
        const color = core[c] * (1 - hot) + hotValues[c] * hot;
        out[i + c] = Math.min(color * (1 - limb[c] * (1 - mu)) * texture * 1.18, 1) * strength * 255;
      }
      out[i + 3] = alpha * 255;
    }
  }
  context.putImageData(image, 0, 0);
  return canvas;
}

/** Fine, roughly cellular value noise in about -1...1. */
function granulation(x: number, y: number): number {
  const fx = (x + 1) * 6, fy = (y + 1) * 6;
  const ix = Math.floor(fx), iy = Math.floor(fy);
  const tx = fx - ix, ty = fy - iy;
  const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
  const hash = (a: number, b: number) => {
    const h = Math.sin(a * 127.1 + b * 311.7) * 43_758.5453;
    return (h - Math.floor(h)) * 2 - 1;
  };
  const top = hash(ix, iy) * (1 - sx) + hash(ix + 1, iy) * sx;
  const bottom = hash(ix, iy + 1) * (1 - sx) + hash(ix + 1, iy + 1) * sx;
  return top * (1 - sy) + bottom * sy;
}
