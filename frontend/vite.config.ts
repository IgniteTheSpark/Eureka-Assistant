/// <reference types="node" />
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    port: 5173,
    proxy: {
      // /api/* → backend (FastAPI on :8000). Keeps same-origin in dev so SSE +
      // cookies behave like prod. Production deploy can fold both behind the
      // same domain or use VITE_API_BASE override.
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
        ws: false,
      },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    globals: true,
  },
});
