import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { SenseRingEffects } from "./SenseRingEffects";

describe("SenseRingEffects", () => {
  it("renders two distinct Chinese voice-state cards without step numbers", () => {
    const { container } = render(<SenseRingEffects />);

    expect(screen.getByText("正在聆听")).toBeInTheDocument();
    expect(screen.getByText("正在转写")).toBeInTheDocument();
    expect(container.querySelectorAll(".sense-speech-card")).toHaveLength(2);
    expect(container.querySelectorAll(".sense-speech-card > span")).toHaveLength(0);
    expect(container.querySelector(".sense-speech-arc")).not.toBeInTheDocument();
  });

  it("exposes exactly seven numbered gesture pills", () => {
    const { container } = render(<SenseRingEffects />);

    ["单击", "双击", "三击", "上滑", "下滑", "左滑", "右滑"].forEach(
      (gesture) => expect(screen.getByText(gesture)).toBeInTheDocument(),
    );
    expect(container.querySelectorAll(".sense-gesture-pill")).toHaveLength(7);
    expect(container.querySelectorAll(".sense-gesture-pill-index")).toHaveLength(7);
    expect(screen.queryByText("长按")).not.toBeInTheDocument();
  });

  it("renders three labeled side-mounted haptic ring illustrations", () => {
    const { container } = render(<SenseRingEffects />);

    ["强烈", "连续", "渐强"].forEach((haptic) =>
      expect(screen.getByText(haptic)).toBeInTheDocument(),
    );
    expect(container.querySelectorAll(".haptic-pattern")).toHaveLength(3);
    expect(container.querySelectorAll(".haptic-ring-illustration")).toHaveLength(3);
    expect(container.querySelectorAll(".haptic-ring-outline")).toHaveLength(3);
    expect(
      container.querySelector('[data-haptic-placement="right-field"]'),
    ).toBeInTheDocument();
    expect(
      container.querySelector('[data-haptic-proximity="close"]'),
    ).toBeInTheDocument();
    expect(container.querySelector(".haptic-strong .haptic-burst")).toBeInTheDocument();
    expect(
      container.querySelector(".haptic-continuous .haptic-continuous-wave"),
    ).toBeInTheDocument();
    expect(
      container.querySelector(".haptic-rising .haptic-rising-wave"),
    ).toBeInTheDocument();
  });
});
