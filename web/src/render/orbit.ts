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

const textures: { earth?: Texture; night?: Texture; moon?: Texture; sky?: Texture } = {};
/** NASA SDO's HMI intensitygram: the real sun, disc filling the square. */
let sunImage: HTMLImageElement | undefined;

export async function loadSunImage(url: string): Promise<void> {
  const image = new Image();
  image.src = url;
  await image.decode();
  sunImage = image;
}

/** NASA's Blue Marble (day), Black Marble (night lights), the moon, and the Deep Star Map sky. */
export async function loadOrbitTextures(earthUrl: string, nightUrl: string, moonUrl: string, skyUrl: string): Promise<void> {
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
  [textures.earth, textures.night, textures.moon, textures.sky] = await Promise.all([
    load(earthUrl), load(nightUrl), load(moonUrl), load(skyUrl),
  ]);
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

  // The sky and the sun are at infinity, drawn with a wide fisheye view behind the
  // (orthographic) Earth and moon.
  const sky = { forward, right, up, cx, cy, radius: Math.hypot(cx, cy) };
  drawSky(ctx, sky, canvas.width, canvas.height);
  drawSun(ctx, sun, sky, canvas.width, canvas.height, dpr);

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
      const u = (lon + Math.PI) / (2 * Math.PI), v = (Math.PI / 2 - lat) / Math.PI;
      const color = sample(textures.earth, u, v, [0.2, 0.4, 0.7]);
      const lights = sample(textures.night, u, v, [0.02, 0.02, 0.05]);
      // Daylight with a soft twilight band; city lights come on as it gets dark.
      const light = dot(n, sun);
      const day = Math.min(1, Math.max(0, (light + 0.1) / 0.25));
      const k = 0.04 + 0.95 * day * (0.35 + 0.65 * Math.max(light, 0));
      const dark = (1 - day) * 1.15;
      // A thin bright rim: the atmosphere.
      const rim = Math.pow(1 - z, 3) * 0.6 * (0.3 + 0.7 * day);
      const i = (py * size + px) * 4;
      out[i] = Math.min(255, (color[0] * k + lights[0] * dark + rim * 0.5) * 255);
      out[i + 1] = Math.min(255, (color[1] * k + lights[1] * dark + rim * 0.7) * 255);
      out[i + 2] = Math.min(255, (color[2] * k + lights[2] * dark + rim) * 255);
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

/** How far from the view's center the fisheye reaches at its rim, degrees. */
const skyReach = 100;

interface SkyView {
  forward: Vec;
  right: Vec;
  up: Vec;
  cx: number;
  cy: number;
  /** Fisheye radius in pixels (center to corner). */
  radius: number;
}

/** Where a direction lands in the fisheye: angle from the view's center maps to distance. */
function skyPoint(d: Vec, v: SkyView): { x: number; y: number; angle: number } {
  const angle = Math.acos(Math.max(-1, Math.min(1, dot(d, v.forward)))) * (180 / Math.PI);
  const sx = dot(d, v.right), sy = dot(d, v.up);
  const len = Math.hypot(sx, sy) || 1;
  const r = (angle / skyReach) * v.radius;
  return { x: v.cx + (sx / len) * r, y: v.cy - (sy / len) * r, angle };
}

/**
 * The sky: NASA's Deep Star Map (stars and the Milky Way in celestial coordinates,
 * right ascension increasing to the left with 0h in the middle), turned with the view.
 * Rendered at a lower resolution than the canvas and scaled up; the map is soft anyway.
 */
function drawSky(ctx: CanvasRenderingContext2D, v: SkyView, w: number, h: number) {
  ctx.fillStyle = "#020309";
  ctx.fillRect(0, 0, w, h);
  const t = textures.sky;
  if (!t) return;
  const step = 2;
  const bw = Math.ceil(w / step), bh = Math.ceil(h / step);
  const image = ctx.createImageData(bw, bh);
  const out = image.data;
  for (let by = 0; by < bh; by++) {
    for (let bx = 0; bx < bw; bx++) {
      const dx = bx * step - v.cx, dy = v.cy - by * step;
      const rho = Math.hypot(dx, dy) / v.radius;
      const theta = rad(rho * skyReach);
      const c = rho > 0 ? 1 / (rho * v.radius) : 0;
      const sinT = Math.sin(theta), cosT = Math.cos(theta);
      const d: Vec = [
        v.forward[0] * cosT + (v.right[0] * dx + v.up[0] * dy) * c * sinT,
        v.forward[1] * cosT + (v.right[1] * dx + v.up[1] * dy) * c * sinT,
        v.forward[2] * cosT + (v.right[2] * dx + v.up[2] * dy) * c * sinT,
      ];
      const ra = Math.atan2(d[1], d[0]) / (2 * Math.PI); // turns, -0.5...0.5
      const dec = Math.asin(Math.max(-1, Math.min(1, d[2])));
      const u = ((0.5 - ra) % 1 + 1) % 1;
      const color = sample(t, u, 0.5 - dec / Math.PI, [0, 0, 0]);
      const i = (by * bw + bx) * 4;
      out[i] = color[0] * 255;
      out[i + 1] = color[1] * 255;
      out[i + 2] = color[2] * 255;
      out[i + 3] = 255;
    }
  }
  const scratch = document.createElement("canvas");
  scratch.width = bw;
  scratch.height = bh;
  scratch.getContext("2d")!.putImageData(image, 0, 0);
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(scratch, 0, 0, bw * step, bh * step);
}

/**
 * The sun, on the same sky as the stars. It moves freely, sliding off the frame like
 * anything else; once it's out of view, a small marker at the edge points to it.
 */
function drawSun(ctx: CanvasRenderingContext2D, sun: Vec, v: SkyView, w: number, h: number, dpr: number) {
  const { x, y } = skyPoint(sun, v);
  const r = 60 * dpr;
  // Drawn where it is, even partly off the frame: the canvas clips it.
  const glow = ctx.createRadialGradient(x, y, 0, x, y, r);
  glow.addColorStop(0, "rgba(255, 246, 215, 1)");
  glow.addColorStop(0.2, "rgba(255, 220, 130, 0.95)");
  glow.addColorStop(0.45, "rgba(255, 190, 80, 0.4)");
  glow.addColorStop(1, "rgba(255, 170, 60, 0)");
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
  const sr = 17 * dpr;
  if (sunImage) {
    // The real sun from NASA SDO, with that day's sunspots, in the middle of its glow.
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, sr, 0, Math.PI * 2);
    ctx.clip();
    ctx.drawImage(sunImage, x - sr, y - sr, sr * 2, sr * 2);
    ctx.restore();
  }
  ctx.font = `600 ${11 * dpr}px system-ui, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  ctx.fillStyle = "rgba(255, 230, 180, 0.9)";
  ctx.fillText("Sun", x, y + sr + 6 * dpr);

  // How far the sun's disc is outside the frame; the edge marker fades in over that.
  const outside = Math.max(x - w, -x, y - h, -y) - sr;
  const fade = Math.min(1, Math.max(0, outside / (30 * dpr)));
  if (fade <= 0) return;
  const m = 18 * dpr;
  const ex = Math.max(m, Math.min(w - m, x)), ey = Math.max(m, Math.min(h - m, y));
  const dir = Math.atan2(y - ey, x - ex);
  ctx.save();
  ctx.globalAlpha = fade;
  ctx.translate(ex, ey);
  // An arrowhead pointing off the frame toward the sun.
  ctx.save();
  ctx.rotate(dir);
  ctx.fillStyle = "rgba(255, 205, 110, 0.95)";
  ctx.beginPath();
  ctx.moveTo(9 * dpr, 0);
  ctx.lineTo(-3 * dpr, -6 * dpr);
  ctx.lineTo(-3 * dpr, 6 * dpr);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
  // The label sits on the inward side of the arrow.
  ctx.fillStyle = "rgba(255, 230, 180, 0.95)";
  ctx.textBaseline = "middle";
  const lx = -Math.cos(dir) * 26 * dpr, ly = -Math.sin(dir) * 16 * dpr;
  ctx.fillText("Sun", lx, ly);
  ctx.restore();
}
