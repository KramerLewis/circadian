import { defineConfig } from "vite";

// Relative asset paths, so the build works wherever it's hosted (GitHub Pages serves it
// under /circadian/app/).
export default defineConfig({
  base: "./",
  build: { target: "es2022" },
});
