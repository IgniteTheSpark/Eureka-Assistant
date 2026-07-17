import postcss from "postcss";
import { defineConfig } from "vitest/config";

const demoOnlyBlockMarkers = [
  ["Demo-only application styles: start", "Demo-only application styles: end"],
  ["Flash asset workbench", "Landing motion layout"],
] as const;

const demoOnlySelectorMarkers = [
  ".placeholder-page",
  ".flash-page",
  ".vibe-page",
  ".setup-page",
  ".auth-check",
  ".operator-controls",
  ".auth-form",
  ".auth-error",
  ".auth-actions",
  ".demo-nav",
  ".demo-error",
  ".ring-connection",
  ".connection-status",
  ".connected-ring-visual",
  ".ring-device-",
  ".flash-header",
  ".flash-workspace",
  ".flash-ring-",
  ".flash-canvas",
  ".flash-status-dot",
  ".flash-signal",
  ".asset-card",
  ".vibe-header",
  ".vibe-profiles",
  ".vibe-profile",
  ".vibe-recording",
] as const;

const findDemoOnlyLineRanges = (code: string) => {
  const lines = code.split("\n");

  return demoOnlyBlockMarkers.map(([startMarker, endMarker]) => {
    const start = lines.findIndex((line) => line.includes(startMarker)) + 1;
    const end = lines.findIndex((line) => line.includes(endMarker)) + 1;

    if (start === 0 || end === 0 || end <= start) {
      throw new Error(`Missing CSS isolation markers: ${startMarker} -> ${endMarker}`);
    }

    return [start, end - 1] as const;
  });
};

const isDemoOnlySelector = (selector: string) =>
  demoOnlySelectorMarkers.some((marker) => selector.includes(marker));

const landingStyleBoundary = () => ({
  name: "landing-style-boundary",
  enforce: "pre" as const,
  transform(code: string, id: string) {
    if (!id.endsWith("/src/styles.css")) {
      return null;
    }

    const root = postcss.parse(code, { from: id });
    const demoOnlyLineRanges = findDemoOnlyLineRanges(code);
    const isDemoOnlyLine = (line: number) =>
      demoOnlyLineRanges.some(([start, end]) => line >= start && line <= end);

    root.walkAtRules((atRule) => {
      const line = atRule.source?.start?.line;
      if (line && isDemoOnlyLine(line)) {
        atRule.remove();
      }
    });

    root.walkRules((rule) => {
      const line = rule.source?.start?.line;
      if (line && isDemoOnlyLine(line)) {
        rule.remove();
        return;
      }

      const landingSelectors = rule.selectors.filter(
        (selector) => !isDemoOnlySelector(selector),
      );

      if (landingSelectors.length === 0) {
        rule.remove();
      } else if (landingSelectors.length !== rule.selectors.length) {
        rule.selectors = landingSelectors;
      }
    });

    return { code: root.toString(), map: null };
  },
});

export default defineConfig({
  plugins: [landingStyleBoundary()],
  test: {
    environment: "jsdom",
    environmentOptions: {
      jsdom: { url: "http://localhost:5173" },
    },
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
  },
});
