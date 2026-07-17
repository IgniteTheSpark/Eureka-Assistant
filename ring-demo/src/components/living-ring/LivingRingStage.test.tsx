import "@testing-library/jest-dom/vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { LivingRingStage } from "./LivingRingStage";

vi.mock("./LivingRingScene", async () => {
  const { useEffect } = await import("react");
  return {
    default: ({ onReady }: { onReady: () => void }) => {
      useEffect(() => onReady(), [onReady]);
      return <div className="living-ring-canvas" />;
    },
  };
});

const journeyRef = {
  current: { progress: 0, rotation: 0 },
};

describe("LivingRingStage", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    Reflect.deleteProperty(window, "WebGLRenderingContext");
  });

  it("keeps a product poster visible when WebGL is unavailable", () => {
    render(
      <LivingRingStage
        connectionStatus="disconnected"
        focusedMode={null}
        journeyRef={journeyRef}
        reducedMotion={false}
      />,
    );

    const stage = screen.getByRole("img", { name: "Eureka Ring product" });
    expect(stage).toBeInTheDocument();
    expect(stage).toHaveAttribute("data-product-medium", "realtime-3d");
    expect(stage).not.toHaveAttribute("data-scene-state");
    expect(stage).toHaveAttribute("data-focused-mode", "neutral");
    expect(stage.querySelector("img")).toHaveAttribute(
      "src",
      "/ring/ring-connect.png",
    );
    expect(stage.querySelector(".sense-ring-effects")).toBeInTheDocument();
  });

  it("exposes connection and mode state without adding an interactive surface", () => {
    render(
      <LivingRingStage
        connectionStatus="connected"
        focusedMode="vibe"
        journeyRef={journeyRef}
        reducedMotion={false}
      />,
    );

    const stage = screen.getByTestId("living-ring-stage");
    expect(stage).toHaveAttribute("aria-label", "Eureka Ring product");
    expect(stage).toHaveAttribute("data-connection-status", "connected");
    expect(stage).toHaveAttribute("data-focused-mode", "vibe");
    expect(stage).toHaveAttribute("data-product-medium", "realtime-3d");
    expect(stage).toHaveAttribute("data-handoff-active", "true");
    expect(stage).not.toHaveAttribute("tabindex");
  });

  it("does not hand off the live Ring when reduced motion is enabled", () => {
    render(
      <LivingRingStage
        connectionStatus="connected"
        focusedMode="flash"
        journeyRef={journeyRef}
        reducedMotion
      />,
    );

    expect(screen.getByTestId("living-ring-stage")).toHaveAttribute(
      "data-handoff-active",
      "false",
    );
  });

  it("uses the visible sense section instead of inferring effects from journey progress", async () => {
    const sectionDrivenJourneyRef = {
      current: {
        progress: 0.68,
        rotation: 0,
        effectChapter: "touch" as const,
      },
    };

    render(
      <LivingRingStage
        connectionStatus="disconnected"
        focusedMode={null}
        journeyRef={sectionDrivenJourneyRef}
        reducedMotion={false}
      />,
    );

    await waitFor(() =>
      expect(screen.getByTestId("living-ring-stage")).toHaveAttribute(
        "data-ring-effect-chapter",
        "touch",
      ),
    );
  });

  it("places scan feedback on the exterior presentation layer", () => {
    const { rerender } = render(
      <LivingRingStage
        connectionStatus="scanning"
        focusedMode={null}
        journeyRef={journeyRef}
        reducedMotion={false}
      />,
    );

    expect(screen.getByTestId("living-ring-stage")).toHaveAttribute(
      "data-exterior-sweep",
      "true",
    );

    rerender(
      <LivingRingStage
        connectionStatus="scanning"
        focusedMode={null}
        journeyRef={journeyRef}
        reducedMotion
      />,
    );
    expect(screen.getByTestId("living-ring-stage")).toHaveAttribute(
      "data-exterior-sweep",
      "false",
    );
  });

  it("unmounts the static poster after the WebGL scene becomes ready", async () => {
    Object.defineProperty(window, "WebGLRenderingContext", {
      configurable: true,
      value: class WebGLRenderingContext {},
    });
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(
      {} as RenderingContext,
    );

    render(
      <LivingRingStage
        connectionStatus="disconnected"
        focusedMode={null}
        journeyRef={journeyRef}
        reducedMotion={false}
      />,
    );

    expect(document.querySelector(".living-ring-poster")).toBeInTheDocument();
    await waitFor(() =>
      expect(document.querySelector(".living-ring-canvas")).toBeInTheDocument(),
    );
    await waitFor(() =>
      expect(document.querySelector(".living-ring-poster")).not.toBeInTheDocument(),
    );
  });
});
