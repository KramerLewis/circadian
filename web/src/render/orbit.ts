// The 3D view: Earth in the middle, lit by the sun (day, night and the terminator), a pin
// at the place, Earth's axis, and the moon on its orbit lit from the same direction, so
// its phase is what you'd see from Earth. Drawn per pixel on a 2D canvas, no libraries.
//
// Everything lives in equatorial coordinates (x toward the March equinox, z toward the
// celestial north pole), so the sun and moon come straight from their right ascension
// and declination, and a place on Earth turns with sidereal time. Distances are not to
// scale: the moon's orbit is drawn at a few Earth radii instead of sixty.

import { umbralCoverage } from "../core/eclipse";
import { moonPosition, siderealTime } from "../core/lunar";
import type { Coordinate } from "../core/math";
import { sunPosition } from "../core/solar";

type Vec = [number, number, number];

const dot = (a: Vec, b: Vec) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a: Vec, b: Vec): Vec => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const scale = (a: Vec, k: number): Vec => [a[0] * k, a[1] * k, a[2] * k];
const add = (a: Vec, b: Vec): Vec => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const unit = (a: Vec): Vec => scale(a, 1 / Math.hypot(...a));
const rad = (d: number) => (d * Math.PI) / 180;

/** Unit vector for a right ascension and declination, degrees. */
function direction(ra: number, dec: number): Vec {
  return [Math.cos(rad(dec)) * Math.cos(rad(ra)), Math.cos(rad(dec)) * Math.sin(rad(ra)), Math.sin(rad(dec))];
}

interface Texture {
  width: number;
  height: number;
  pixels: Uint8ClampedArray;
}

const textures: { earth?: Texture; moon?: Texture } = {};

export async function loadOrbitTextures(earthUrl: string, moonUrl: string): Promise<void> {
  const load = async (url: string): Promise<Texture> => {
    const image = new Image();
    image.src = url;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = image.width;
    canvas.height = image.height;
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
    ctx.drawImage(image, 0, 0);
    return { width: image.width, height: image.height, pixels: ctx.getImageData(0, 0, image.width, image.height).data };
  };
  [textures.earth, textures.moon] = await Promise.all([load(earthUrl), load(moonUrl)]);
}

function sample(t: Texture | undefined, u: number, v: number, fallback: Vec): Vec {
  if (!t) return fallback;
  const x = Math.min(t.width - 1, Math.max(0, Math.floor(u * t.width)));
  const y = Math.min(t.height - 1, Math.max(0, Math.floor(v * t.height)));
  const i = (y * t.width + x) * 4;
  if (t.pixels[i + 3] === 0) return fallback;
  return [t.pixels[i] / 255, t.pixels[i + 1] / 255, t.pixels[i + 2] / 255];
}

/** Where the viewer looks from, relative to the default view (which follows the sun). */
export interface OrbitCamera {
  yaw: number;
  pitch: number;
}

export interface OrbitScene {
  now: number;
  place: Coordinate & { name: string };
  dark: boolean;
  camera: OrbitCamera;
}

/** Text and lines over the space background, which is dark in both themes. */
const ink = { text: "rgba(235, 236, 245, 0.85)", faint: "rgba(200, 205, 230, 0.4)" };

/** The moon's orbit radius on screen, in Earth radii. */
const orbitRadius = 3.4;
const moonRadius = 0.42;

export function drawOrbit(canvas: HTMLCanvasElement, scene: OrbitScene): void {
  const width = canvas.clientWidth, height = canvas.clientHeight;
  const dpr = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
  }
  const ctx = canvas.getContext("2d")!;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const sunPos = sunPosition(scene.now);
  const moon = moonPosition(scene.now);
  const sun = direction(sunPos.rightAscension, sunPos.declination);
  const moonDir = direction(moon.rightAscension, moon.declination);
  const moonCenter = scale(moonDir, orbitRadius);
  const north: Vec = [0, 0, 1];

  // The default view looks across the sun-Earth line from above and a little sunward, so
  // most of the day side shows along with the terminator, and the moon's phase reads
  // as it would from Earth.
  const sunAzimuth = Math.atan2(sun[1], sun[0]);
  const azimuth = sunAzimuth - Math.PI / 2 + rad(scene.camera.yaw) + rad(30);
  const elevation = rad(Math.max(-85, Math.min(85, 35 + scene.camera.pitch)));
  const toCamera: Vec = [Math.cos(elevation) * Math.cos(azimuth), Math.cos(elevation) * Math.sin(azimuth), Math.sin(elevation)];
  const forward = scale(toCamera, -1);
  const right = unit(cross(forward, north));
  const up = cross(right, forward);

  // Orthographic projection; px per Earth radius chosen to fit the moon's orbit.
  const s = (Math.min(width, height) / 2 / (orbitRadius + moonRadius + 0.5)) * dpr;
  const cx = (width / 2) * dpr, cy = (height / 2) * dpr;
  const project = (p: Vec): [number, number, number] => [cx + dot(p, right) * s, cy - dot(p, up) * s, dot(p, toCamera)];

  drawStars(ctx, canvas.width, canvas.height, scene.dark);
  drawSunMarker(ctx, project, sun, canvas.width, canvas.height, dpr);

  // The orbit over the month around now, split so the far side passes behind Earth.
  const path: [number, number, number][] = [];
  for (let d = -14.8; d <= 14.8; d += 0.25) {
    const m = moonPosition(scene.now + d * 86_400_000);
    path.push(project(scale(direction(m.rightAscension, m.declination), orbitRadius)));
  }
  const strokeOrbit = (front: boolean) => {
    ctx.strokeStyle = ink.faint;
    ctx.lineWidth = 1.2 * dpr;
    ctx.setLineDash([4 * dpr, 4 * dpr]);
    ctx.beginPath();
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1], b = path[i];
      const isFront = a[2] + b[2] > 0;
      if (isFront !== front) continue;
      ctx.moveTo(a[0], a[1]);
      ctx.lineTo(b[0], b[1]);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  };

  const moonBehind = dot(moonCenter, toCamera) < 0;
  strokeOrbit(false);
  if (moonBehind) drawMoonSphere(ctx, project, moonCenter, sun, toCamera, right, up, s, umbralCoverage(scene.now));
  drawAxis(ctx, project, north, dpr, false);
  drawEarth(ctx, cx, cy, s, sun, toCamera, right, up, scene.now);
  drawAxis(ctx, project, north, dpr, true);
  drawPin(ctx, project, scene, toCamera, dpr);
  strokeOrbit(true);
  if (!moonBehind) drawMoonSphere(ctx, project, moonCenter, sun, toCamera, right, up, s, umbralCoverage(scene.now));

  ctx.fillStyle = ink.text;
  ctx.font = `${11 * dpr}px system-ui, sans-serif`;
  ctx.textAlign = "left";
  ctx.textBaseline = "bottom";
  ctx.fillText("Not to scale · drag to turn", 8 * dpr, canvas.height - 6 * dpr);
}

function drawEarth(
  ctx: CanvasRenderingContext2D, cx: number, cy: number, s: number, sun: Vec, toCamera: Vec, right: Vec, up: Vec, now: number,
) {
  const r = Math.ceil(s);
  const size = r * 2 + 2;
  const image = ctx.createImageData(size, size);
  const out = image.data;
  const turn = rad(siderealTime(now));
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      const x = (px - r - 0.5) / s, y = (r + 0.5 - py) / s;
      const d2 = x * x + y * y;
      if (d2 > 1) continue;
      const z = Math.sqrt(1 - d2);
      // Surface normal in equatorial coordinates.
      const n = add(add(scale(right, x), scale(up, y)), scale(toCamera, z));
      const lat = Math.asin(Math.max(-1, Math.min(1, n[2])));
      let lon = Math.atan2(n[1], n[0]) - turn;
      lon = ((((lon + Math.PI) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)) - Math.PI;
      const color = sample(textures.earth, (lon + Math.PI) / (2 * Math.PI), (Math.PI / 2 - lat) / Math.PI, [0.2, 0.4, 0.7]);
      // Daylight with a soft twilight band; the night side keeps a faint blue.
      const light = dot(n, sun);
      const day = Math.min(1, Math.max(0, (light + 0.1) / 0.25));
      const k = 0.1 + 0.95 * day * (0.35 + 0.65 * Math.max(light, 0));
      // A thin bright rim: the atmosphere.
      const rim = Math.pow(1 - z, 3) * 0.6 * (0.3 + 0.7 * day);
      const i = (py * size + px) * 4;
      out[i] = Math.min(255, (color[0] * k + rim * 0.5) * 255);
      out[i + 1] = Math.min(255, (color[1] * k + rim * 0.7) * 255);
      out[i + 2] = Math.min(255, (color[2] * k + 0.03 * (1 - day) + rim) * 255);
      out[i + 3] = Math.min(1, (1 - Math.sqrt(d2)) * s) * 255;
    }
  }
  // Draw via a scratch canvas so the disc's transparent corners blend.
  const scratch = document.createElement("canvas");
  scratch.width = scratch.height = size;
  scratch.getContext("2d")!.putImageData(image, 0, 0);
  const glow = ctx.createRadialGradient(cx, cy, s * 0.98, cx, cy, s * 1.18);
  glow.addColorStop(0, "rgba(120, 170, 255, 0.35)");
  glow.addColorStop(1, "rgba(120, 170, 255, 0)");
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, s * 1.18, 0, Math.PI * 2);
  ctx.fill();
  ctx.drawImage(scratch, cx - r - 1, cy - r - 1);
}

function drawMoonSphere(
  ctx: CanvasRenderingContext2D, project: (p: Vec) => [number, number, number], center: Vec, sun: Vec,
  toCamera: Vec, right: Vec, up: Vec, s: number, shadow: number,
) {
  const [mx, my] = project(center);
  const rr = moonRadius * s;
  const r = Math.ceil(rr);
  const size = r * 2 + 2;
  const image = ctx.createImageData(size, size);
  const out = image.data;
  // The near side faces Earth: map the texture onto that hemisphere, north up.
  const toEarth = unit(scale(center, -1));
  const east = unit(cross([0, 0, 1], toEarth));
  const northOnDisc = cross(toEarth, east);
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      const x = (px - r - 0.5) / rr, y = (r + 0.5 - py) / rr;
      const d2 = x * x + y * y;
      if (d2 > 1) continue;
      const z = Math.sqrt(1 - d2);
      const n = add(add(scale(right, x), scale(up, y)), scale(toCamera, z));
      const facing = dot(n, toEarth);
      // Seen from Earth the near side is mirrored left-right relative to "east".
      const color: Vec = facing > 0
        ? sample(textures.moon, (1 - dot(n, east)) / 2, (1 - dot(n, northOnDisc)) / 2, [0.75, 0.74, 0.72])
        : [0.62, 0.61, 0.6];
      const light = Math.max(0, dot(n, sun));
      let k = 0.06 + 1.05 * Math.min(1, light * 1.6);
      let tint: Vec = [1, 1, 1];
      if (shadow > 0) {
        // In Earth's shadow: dim and copper-red, as in a lunar eclipse.
        tint = [1 - 0.15 * shadow, 1 - 0.7 * shadow, 1 - 0.82 * shadow];
        k *= 1 - 0.55 * shadow;
      }
      const i = (py * size + px) * 4;
      out[i] = Math.min(255, color[0] * k * tint[0] * 255);
      out[i + 1] = Math.min(255, color[1] * k * tint[1] * 255);
      out[i + 2] = Math.min(255, color[2] * k * tint[2] * 255);
      out[i + 3] = Math.min(1, (1 - Math.sqrt(d2)) * rr) * 255;
    }
  }
  const scratch = document.createElement("canvas");
  scratch.width = scratch.height = size;
  scratch.getContext("2d")!.putImageData(image, 0, 0);
  ctx.drawImage(scratch, mx - r - 1, my - r - 1);
}

/** Earth's axis, through the poles; the half behind Earth is drawn first. */
function drawAxis(
  ctx: CanvasRenderingContext2D, project: (p: Vec) => [number, number, number], north: Vec, dpr: number, front: boolean,
) {
  ctx.strokeStyle = ink.text;
  ctx.lineWidth = 1.2 * dpr;
  for (const sign of [1, -1]) {
    const tip = project(scale(north, 1.45 * sign));
    const base = project(scale(north, 1.0 * sign));
    if (base[2] > 0 !== front) continue;
    ctx.beginPath();
    ctx.moveTo(base[0], base[1]);
    ctx.lineTo(tip[0], tip[1]);
    ctx.stroke();
    if (sign > 0) {
      ctx.fillStyle = ink.text;
      ctx.font = `${10 * dpr}px system-ui, sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "bottom";
      ctx.fillText("N", tip[0], tip[1] - 2 * dpr);
    }
  }
}

/** A pin at the place, on the side of Earth facing the viewer (or a faint one behind). */
function drawPin(ctx: CanvasRenderingContext2D, project: (p: Vec) => [number, number, number], scene: OrbitScene, toCamera: Vec, dpr: number) {
  const ra = siderealTime(scene.now) + scene.place.longitude;
  const p = direction(ra, scene.place.latitude);
  const visible = dot(p, toCamera) > 0;
  const [x, y] = project(scale(p, 1.0));
  ctx.save();
  ctx.globalAlpha = visible ? 1 : 0.35;
  ctx.fillStyle = "#ff5a3c";
  ctx.strokeStyle = "white";
  ctx.lineWidth = 1.5 * dpr;
  ctx.beginPath();
  ctx.arc(x, y, 4 * dpr, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();
  if (visible) {
    ctx.font = `600 ${11 * dpr}px system-ui, sans-serif`;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 3 * dpr;
    ctx.strokeStyle = "rgba(0, 0, 0, 0.55)";
    ctx.strokeText(scene.place.name, x + 7 * dpr, y);
    ctx.fillStyle = "white";
    ctx.fillText(scene.place.name, x + 7 * dpr, y);
  }
  ctx.restore();
}

/** The sun is far off: a glow at the edge of the view in its direction, labeled. */
function drawSunMarker(
  ctx: CanvasRenderingContext2D, project: (p: Vec) => [number, number, number], sun: Vec, w: number, h: number, dpr: number,
) {
  const [ox, oy] = project([0, 0, 0]);
  const [sx, sy] = project(sun);
  let dx = sx - ox, dy = sy - oy;
  const len = Math.hypot(dx, dy) || 1;
  dx /= len;
  dy /= len;
  // Push it out to just inside the frame.
  const margin = 26 * dpr;
  const t = Math.min(
    dx > 0 ? (w - margin - ox) / dx : dx < 0 ? (margin - ox) / dx : Infinity,
    dy > 0 ? (h - margin - oy) / dy : dy < 0 ? (margin - oy) / dy : Infinity,
  );
  const x = ox + dx * t, y = oy + dy * t;
  const glow = ctx.createRadialGradient(x, y, 0, x, y, 40 * dpr);
  glow.addColorStop(0, "rgba(255, 236, 170, 1)");
  glow.addColorStop(0.25, "rgba(255, 200, 90, 0.75)");
  glow.addColorStop(1, "rgba(255, 170, 60, 0)");
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(x, y, 40 * dpr, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "rgba(120, 70, 0, 0.9)";
  ctx.font = `600 ${11 * dpr}px system-ui, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("Sun", x, y);
}

function drawStars(ctx: CanvasRenderingContext2D, w: number, h: number, dark: boolean) {
  ctx.fillStyle = dark ? "#05060d" : "#10142a";
  ctx.fillRect(0, 0, w, h);
  let seed = 7;
  const random = () => {
    seed = (seed * 16807) % 2147483647;
    return seed / 2147483647;
  };
  for (let i = 0; i < 140; i++) {
    const x = random() * w, y = random() * h, size = 0.4 + random() * 1.2;
    ctx.fillStyle = `rgba(255, 255, 255, ${0.25 + 0.6 * random()})`;
    ctx.fillRect(x, y, size, size);
  }
}
