import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** A fixture from shared/fixtures, shared by every platform's tests. */
export function fixture<T>(name: string): T {
  const url = new URL(`../../shared/fixtures/${name}`, import.meta.url);
  return JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as T;
}

export const instant = (iso: string): number => {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) throw new Error(`bad date ${iso}`);
  return t;
};
