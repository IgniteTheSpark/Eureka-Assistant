import { mergeConfig } from "vite";
import { defineConfig } from "vitest/config";

import baseConfig from "./vite.config";

export default mergeConfig(
  baseConfig,
  defineConfig({
    test: {
      include: [
        "src/app/**/*.test.ts",
        "src/app/**/*.test.tsx",
        "src/pages/HomePage.test.tsx",
        "src/components/landing/**/*.test.ts",
        "src/components/landing/**/*.test.tsx",
        "src/components/living-ring/**/*.test.ts",
        "src/components/living-ring/**/*.test.tsx"
      ]
    }
  }),
);
