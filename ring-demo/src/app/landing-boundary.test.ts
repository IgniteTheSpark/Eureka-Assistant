import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const projectRoot = resolve(import.meta.dirname, "../..");

describe("landing application boundary", () => {
  it("uses landing-only build, typecheck, and test commands by default", () => {
    const packageJson = JSON.parse(
      readFileSync(resolve(projectRoot, "package.json"), "utf8"),
    ) as { scripts: Record<string, string> };

    expect(packageJson.scripts.build).toContain("tsconfig.landing.json");
    expect(packageJson.scripts.typecheck).toContain("tsconfig.landing.json");
    expect(packageJson.scripts.test).toContain("vitest.landing.config.ts");
  });

  it("keeps Flash and Vibe demo entry files outside the landing compiler", () => {
    const landingConfig = JSON.parse(
      readFileSync(resolve(projectRoot, "tsconfig.landing.json"), "utf8"),
    ) as { exclude?: string[]; include?: string[] };

    expect(landingConfig.include).toContain("src/pages/HomePage.tsx");
    expect(landingConfig.include).not.toContain("src/pages/*.tsx");
    expect(landingConfig.exclude).toEqual(
      expect.arrayContaining([
        "src/pages/FlashPage.tsx",
        "src/pages/VibePage.tsx",
        "src/state/demo-store.tsx",
      ]),
    );
  });

  it("retains explicit commands for validating the isolated demo code", () => {
    const packageJson = JSON.parse(
      readFileSync(resolve(projectRoot, "package.json"), "utf8"),
    ) as { scripts: Record<string, string> };

    expect(packageJson.scripts["test:demo"]).toContain("vitest.demo.config.ts");
    expect(packageJson.scripts["typecheck:demo"]).toContain("tsconfig.demo.json");
  });
});
