// The moon as it looks now: NASA's LRO albedo map (public/moon.png, from
// ios/tools/make_moon_texture.py) lit for the phase with Lommel-Seeliger shading, faint
// earthshine on the dark side, and a copper-red tint inside Earth's shadow during a
// lunar eclipse. A port of ios/Shared/MoonRenderer.swift.

import type { Phase } from "../core/lunar";

interface Texture {
  width: number;
  height: number;
  pixels: Uint8ClampedArray;
}

let texture: Texture | undefined;
const cache = new Map<string, HTMLCanvasElement>();

/** Loads the texture; until it arrives the moon is drawn plain gray. */
export async function loadMoonTexture(url: string): Promise<void> {
  const image = new Image();
  image.src = url;
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = image.width;
  canvas.height = image.height;
  const context = canvas.getContext("2d", { willReadFrequently: true })!;
  context.drawImage(image, 0, 0);
  texture = { width: image.width, height: image.height, pixels: context.getImageData(0, 0, image.width, image.height).data };
  cache.clear();
}

/** `shadow` (0...1) is how far the moon is inside Earth's umbra. */
export function moonImage(phase: Phase, southern: boolean, pixels: number, shadow = 0): HTMLCanvasElement {
  const illumination = Math.round(phase.illumination * 1000);
  const n = Math.max(Math.ceil(pixels), 8);
  const shadowSteps = Math.round(Math.min(Math.max(shadow, 0), 1) * 20);
  const key = `${illumination}|${phase.isWaxing}|${southern}|${n}|${shadowSteps}|${!!texture}`;
  let canvas = cache.get(key);
  if (!canvas) {
    canvas = render(illumination / 1000, phase.isWaxing, southern, n, shadowSteps / 20);
    if (cache.size > 24) cache.clear();
    cache.set(key, canvas);
  }
  return canvas;
}

function render(k: number, waxing: boolean, southern: boolean, n: number, shadow: number): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = n;
  const context = canvas.getContext("2d")!;
  const image = context.createImageData(n, n);
  const out = image.data;
  // Sun direction in view space (x right, z toward the viewer). From the northern
  // hemisphere a waxing moon is lit on the right.
  const elongation = Math.acos(Math.min(Math.max(1 - 2 * k, -1), 1));
  const side = waxing !== southern ? 1 : -1;
  const sunX = side * Math.sin(elongation), sunZ = -Math.cos(elongation);
  const half = n / 2;
  for (let row = 0; row < n; row++) {
    for (let col = 0; col < n; col++) {
      const x = (col + 0.5 - half) / half;
      const y = (half - row - 0.5) / half;
      const r2 = x * x + y * y;
      if (r2 >= 1 + 2 / half) continue;
      const alpha = Math.min(Math.max((1 - Math.sqrt(r2)) * half, 0), 1);
      if (alpha <= 0) continue;
      const z = Math.sqrt(Math.max(1 - r2, 0));
      const mu0 = x * sunX + z * sunZ;
      const lit = mu0 > 0 ? Math.min((2 * mu0) / (mu0 + z + 1e-6), 1) : 0;
      // From the southern hemisphere the moon appears rotated 180 degrees.
      const [red, green, blue] = sample(southern ? -x : x, southern ? -y : y);
      const earthshine = 0.07 * (1 - lit);
      let r = Math.min(red * 1.15 * lit + red * earthshine * 0.6, 1);
      let g = Math.min(green * 1.15 * lit + green * earthshine * 0.7, 1);
      let b = Math.min(blue * 1.15 * lit + blue * earthshine * 1.0, 1);
      if (shadow > 0) {
        // Sunlight bent through Earth's atmosphere: a dim copper-red moon.
        const gray = 0.3 * r + 0.59 * g + 0.11 * b;
        r = r * (1 - shadow) + gray * 0.85 * shadow;
        g = g * (1 - shadow) + gray * 0.22 * shadow;
        b = b * (1 - shadow) + gray * 0.1 * shadow;
      }
      // Like the real moon in a lit sky, the unlit part is mostly see-through.
      const a = alpha * (0.18 + 0.82 * Math.min(lit * 2, 1));
      const i = (row * n + col) * 4;
      // ImageData isn't premultiplied, so the color is stored as is.
      out[i] = r * 255;
      out[i + 1] = g * 255;
      out[i + 2] = b * 255;
      out[i + 3] = a * 255;
    }
  }
  context.putImageData(image, 0, 0);
  return canvas;
}

/** Bilinear sample of the albedo texture at disc coordinates (-1...1, y up). */
function sample(x: number, y: number): [number, number, number] {
  const t = texture;
  const gray: [number, number, number] = [0.78, 0.77, 0.74];
  if (!t) return gray;
  const u = Math.min(Math.max(((x + 1) / 2) * (t.width - 1), 0), t.width - 1);
  const v = Math.min(Math.max(((1 - y) / 2) * (t.height - 1), 0), t.height - 1);
  const u0 = Math.floor(u), v0 = Math.floor(v);
  const u1 = Math.min(u0 + 1, t.width - 1), v1 = Math.min(v0 + 1, t.height - 1);
  const fu = u - u0, fv = v - v0;
  const px = (cu: number, cv: number): [number, number, number] => {
    const i = (cv * t.width + cu) * 4;
    if (t.pixels[i + 3] === 0) return gray;
    return [t.pixels[i] / 255, t.pixels[i + 1] / 255, t.pixels[i + 2] / 255];
  };
  const p00 = px(u0, v0), p10 = px(u1, v0), p01 = px(u0, v1), p11 = px(u1, v1);
  const mix = (c: number) => (p00[c] * (1 - fu) + p10[c] * fu) * (1 - fv) + (p01[c] * (1 - fu) + p11[c] * fu) * fv;
  return [mix(0), mix(1), mix(2)];
}
