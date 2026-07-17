import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { ModeSceneStage } from "./ModeSceneStage";

function renderStage(
  focusedMode: "flash" | "vibe" | null = null,
  onFocusMode = vi.fn(),
) {
  return render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
    >
      <ModeSceneStage
        focusedMode={focusedMode}
        onFocusMode={onFocusMode}
        reducedMotion={false}
      />
    </MemoryRouter>,
  );
}

describe("ModeSceneStage", () => {
  it("keeps both scenes present without exposing demo routes", () => {
    const onFocusMode = vi.fn();
    renderStage(null, onFocusMode);

    const flash = screen.getByRole("article", { name: "Flash Mode｜闪念" });
    const vibe = screen.getByRole("article", { name: "Vibe Mode｜随声操控" });
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
    expect(screen.queryByText(/进入 Flash|进入 Vibe/)).not.toBeInTheDocument();

    fireEvent.pointerEnter(flash);
    expect(onFocusMode).toHaveBeenLastCalledWith("flash");
    fireEvent.pointerLeave(flash);
    expect(onFocusMode).toHaveBeenLastCalledWith(null);
    fireEvent.focus(vibe);
    expect(onFocusMode).toHaveBeenLastCalledWith("vibe");
    fireEvent.blur(vibe);
    expect(onFocusMode).toHaveBeenLastCalledWith(null);
  });

  it("uses touch press only as visual intent", () => {
    const onFocusMode = vi.fn();
    renderStage(null, onFocusMode);

    const flash = screen.getByRole("article", { name: "Flash Mode｜闪念" });
    fireEvent.touchStart(flash);

    expect(onFocusMode).toHaveBeenLastCalledWith("flash");
  });

  it("uses stable stage hot zones so the moving grid cannot trap hover", () => {
    const onFocusMode = vi.fn();
    renderStage("flash", onFocusMode);
    const stage = screen.getByTestId("mode-scene-stage");
    vi.spyOn(stage, "getBoundingClientRect").mockReturnValue({
      bottom: 800,
      height: 800,
      left: 100,
      right: 1100,
      top: 0,
      width: 1000,
      x: 100,
      y: 0,
      toJSON: () => ({}),
    });

    fireEvent(stage, new MouseEvent("pointermove", { bubbles: true, clientX: 600 }));
    expect(onFocusMode).toHaveBeenLastCalledWith(null);

    fireEvent(stage, new MouseEvent("pointermove", { bubbles: true, clientX: 300 }));
    expect(onFocusMode).toHaveBeenLastCalledWith("flash");

    fireEvent(stage, new MouseEvent("pointermove", { bubbles: true, clientX: 900 }));
    expect(onFocusMode).toHaveBeenLastCalledWith("vibe");
  });

  it("retains commands and speaking hints as semantic HTML", () => {
    renderStage("flash");

    expect(
      screen.getByText("帮我安排 Kevin 下午四点到五点的会议。"),
    ).toBeInTheDocument();
    expect(
      screen.getByText("帮我执行这个计划，并把代码推送到 GitHub。"),
    ).toBeInTheDocument();
    expect(
      screen.getAllByText("自然表达，安静捕捉。"),
    ).toHaveLength(2);
  });

  it("exposes neutral and focused layout state to CSS", () => {
    const { rerender } = renderStage();

    expect(screen.getByTestId("mode-scene-stage")).toHaveAttribute(
      "data-focused-mode",
      "neutral",
    );

    rerender(
      <MemoryRouter
        future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      >
        <ModeSceneStage
          focusedMode="vibe"
          onFocusMode={vi.fn()}
          reducedMotion={false}
        />
      </MemoryRouter>,
    );

    expect(screen.getByTestId("mode-scene-stage")).toHaveAttribute(
      "data-focused-mode",
      "vibe",
    );
  });
});
