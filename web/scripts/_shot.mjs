import { chromium } from "playwright";
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 665, height: 265 }, deviceScaleFactor: 2 })).newPage();
await p.goto("file://" + process.argv[2]); await p.screenshot({ path: process.argv[3] }); await b.close();
