import { mergeConfig } from "vite";
import { defineConfig } from "vitest/config";

import baseConfig from "./vite.config";

export default mergeConfig(
  baseConfig,
  defineConfig({
    test: {
      include: [
        "src/pages/FlashPage.test.tsx",
        "src/pages/VibePage.test.tsx",
        "src/pages/SetupPage.test.tsx",
        "src/state/**/*.test.ts",
        "src/state/**/*.test.tsx",
        "src/features/**/*.test.ts",
        "src/features/**/*.test.tsx",
        "src/lib/**/*.test.ts",
        "src/lib/**/*.test.tsx",
        "src/components/AssetCard.test.tsx",
        "src/components/OperatorControls.test.tsx",
        "src/components/RingConnection.test.tsx",
        "src/components/ScrollStack.test.tsx",
        "src/components/mode-scenes/**/*.test.ts",
        "src/components/mode-scenes/**/*.test.tsx"
      ]
    }
  }),
);
