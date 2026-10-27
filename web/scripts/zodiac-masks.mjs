// Bakes the zodiac line art (shared/assets/zodiac/*.svg, black ink on white) into the
// masks the wadokei center draws: white ink on transparent, trimmed to the drawing and
// centered in a square, so every animal fills the center the same way.
//
//   node scripts/zodiac-masks.mjs   → public/zodiac/<animal>.png

import { readFile, mkdir, writeFile, readdir } from "node:fs/promises";
import { chromium } from "playwright";

const source = new URL("../../shared/assets/zodiac/", import.meta.url);
const target = new URL("../public/zodiac/", import.meta.url);
const side = 384;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.route("https://zodiac.invalid/**", async (route) => {
  const name = route.request().url().split("/").pop();
  if (!name.endsWith(".svg")) return route.fulfill({ contentType: "text/html", body: "<!doctype html>" });
  route.fulfill({ contentType: "image/svg+xml", body: await readFile(new URL(name, source)) });
});
await page.goto("https://zodiac.invalid/");
await mkdir(target, { recursive: true });

for (const file of (await readdir(source)).filter((f) => f.endsWith(".svg")).sort()) {
  const png = await page.evaluate(async ({ file, side }) => {
    const img = new Image();
    img.src = file;
    await img.decode();
    // Ink: dark pixels opaque, light ones clear (the traces' gray edges become soft alpha).
    const work = 1024;
    const c = document.createElement("canvas");
    c.width = c.height = work;
    const k = c.getContext("2d");
    k.fillStyle = "white";
    k.fillRect(0, 0, work, work);
    k.drawImage(img, 0, 0, work, work);
    const d = k.getImageData(0, 0, work, work);
    let [x0, y0, x1, y1] = [work, work, 0, 0];
    for (let i = 0; i < work * work; i++) {
      const p = i * 4;
      const l = (d.data[p] + d.data[p + 1] + d.data[p + 2]) / 3;
      const a = Math.max(0, Math.min(255, ((200 - l) * 255) / 120));
      d.data[p] = d.data[p + 1] = d.data[p + 2] = 255;
      d.data[p + 3] = a;
      if (a > 32) {
        const x = i % work, y = (i / work) | 0;
        x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      }
    }
    k.putImageData(d, 0, 0);
    const out = document.createElement("canvas");
    out.width = out.height = side;
    const w = x1 - x0 + 1, h = y1 - y0 + 1;
    const fit = (side * 0.96) / Math.max(w, h);
    out.getContext("2d").drawImage(c, x0, y0, w, h, (side - w * fit) / 2, (side - h * fit) / 2, w * fit, h * fit);
    return out.toDataURL("image/png");
  }, { file, side });
  const name = file.replace(/\.svg$/, ".png");
  const bytes = Buffer.from(png.split(",")[1], "base64");
  await writeFile(new URL(name, target), bytes);
  console.log(`${name} ${(bytes.length / 1024).toFixed(0)} KB`);
}
await browser.close();
