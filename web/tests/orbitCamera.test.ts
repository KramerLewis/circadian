import { expect, test } from "vitest";
import { defaultOrbitCamera, setNorthUp, turnOrbitCamera, turnOrbitCameraNorthUp } from "../src/render/orbit";

// In the default view's axes, Earth's north is (0, cos 35°, sin 35°).
const north = [0, Math.cos((35 * Math.PI) / 180), Math.sin((35 * Math.PI) / 180)];
const dot = (a: number[], b: number[]) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

test("north-locked turning keeps north straight up and stops short of the poles", () => {
  const camera = defaultOrbitCamera();
  for (let i = 0; i < 20; i++) turnOrbitCameraNorthUp(camera, 13, 9);
  expect(Math.abs(dot(north, camera.right))).toBeLessThan(1e-9);
  expect(dot(north, camera.up)).toBeGreaterThan(0);
  // 180 degrees of tilt requested from 35 degrees up: it stops at 85.
  expect(Math.asin(dot(north, camera.back)) * (180 / Math.PI)).toBeCloseTo(85, 6);
});

test("a sideways drag swings the view the same way locked and unlocked", () => {
  const free = defaultOrbitCamera(), locked = defaultOrbitCamera();
  turnOrbitCamera(free, 10, 0);
  turnOrbitCameraNorthUp(locked, 10, 0);
  // Both move the viewpoint toward the camera's right.
  expect(free.back[0]).toBeGreaterThan(0);
  expect(locked.back[0]).toBeGreaterThan(0);
});

test("setting north up removes any roll", () => {
  const camera = defaultOrbitCamera();
  turnOrbitCamera(camera, 40, 70);
  setNorthUp(camera);
  expect(Math.abs(dot(north, camera.right))).toBeLessThan(1e-9);
});
