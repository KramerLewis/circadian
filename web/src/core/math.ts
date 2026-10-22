export const radians = (degrees: number): number => (degrees * Math.PI) / 180;
export const degrees = (radians: number): number => (radians * 180) / Math.PI;

/** x mod m in [0, m). */
export function mod(x: number, m: number): number {
  const r = x % m;
  return r < 0 ? r + m : r;
}

/** Wraps degrees to (-180, 180]. */
export function normalize(x: number): number {
  let d = x % 360;
  if (d <= -180) d += 360;
  else if (d > 180) d -= 360;
  return d;
}

export const rev = (x: number): number => mod(x, 360);

export const clamp = (x: number, lo: number, hi: number): number => Math.min(Math.max(x, lo), hi);

export interface Coordinate {
  latitude: number;
  /** Positive east. */
  longitude: number;
}
