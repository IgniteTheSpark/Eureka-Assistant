import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";

import {
  FlashJourneyDock,
  type FlashJourneyPhase,
} from "./FlashJourneyDock";

vi.mock("../../components/Dither", () => ({
  Dither: (props: { waveColor: [number, number, number] }) => (
    <output data-testid="dock-dither">{props.waveColor.join(",")}</output>
  ),
}));

it.each([
  ["listening", "Capturing", "0.32,0.57,1"],
  ["transcribing", "Transcribing", "0.67,0.47,0.9"],
  ["analyzing", "Analyzing", "0.18,0.76,0.73"],
  ["created", "Generated", "0.28,0.73,0.48"],
] as const)(
  "uses stable content geometry and the approved palette during %s",
  (phase, title, palette) => {
    render(
      <FlashJourneyDock
        createdCount={2}
        error={null}
        onDismiss={vi.fn()}
        onRetry={vi.fn()}
        phase={phase}
        transcript={phase === "listening" ? "" : "联系 Alex"}
      />,
    );

    expect(screen.getByRole("heading", { name: title })).toBeVisible();
    expect(screen.getByRole("heading", { name: title })).toHaveClass(
      "flash-journey-title",
    );
    expect(screen.getByTestId("dock-dither")).toHaveTextContent(palette);
    expect(document.querySelector(".flash-journey-transcript")).toBeVisible();
    expect(document.querySelector(".flash-journey-center")).toBeVisible();
    expect(document.querySelector(".flash-journey-footer")).toBeVisible();
  },
);

it("keeps the transcript in its top rail through analysis and completion", () => {
  const { rerender } = render(
    <FlashJourneyDock
      createdCount={0}
      error={null}
      onDismiss={vi.fn()}
      onRetry={vi.fn()}
      phase="transcribing"
      transcript="联系 Alex"
    />,
  );

  expect(screen.getByText("联系 Alex")).toHaveClass("flash-journey-transcript");

  rerender(
    <FlashJourneyDock
      createdCount={2}
      error={null}
      onDismiss={vi.fn()}
      onRetry={vi.fn()}
      phase="created"
      transcript="联系 Alex"
    />,
  );
  expect(screen.getByText("联系 Alex")).toHaveClass("flash-journey-transcript");
  expect(screen.getByText("2 cards added")).toBeVisible();
});

it("uses singular completion copy for one created card", () => {
  render(
    <FlashJourneyDock
      createdCount={1}
      error={null}
      onDismiss={vi.fn()}
      onRetry={vi.fn()}
      phase="created"
      transcript="记下一件事"
    />,
  );

  expect(screen.getByText("1 card added")).toBeVisible();
});

it.each(["ready", "settled", "disconnected"] as FlashJourneyPhase[])(
  "hides during %s",
  (phase) => {
    const { container } = render(
      <FlashJourneyDock
        createdCount={0}
        error={null}
        onDismiss={vi.fn()}
        onRetry={vi.fn()}
        phase={phase}
        transcript=""
      />,
    );
    expect(container).toBeEmptyDOMElement();
  },
);

it("uses Dither without a redundant live wave and retains compact retry context", () => {
  const onRetry = vi.fn();
  const { rerender } = render(
    <FlashJourneyDock
      createdCount={0}
      error={null}
      onDismiss={vi.fn()}
      onRetry={onRetry}
      phase="listening"
      transcript=""
    />,
  );
  expect(screen.queryByTestId("live-wave")).not.toBeInTheDocument();

  rerender(
    <FlashJourneyDock
      createdCount={0}
      error={null}
      onDismiss={vi.fn()}
      onRetry={onRetry}
      phase="transcribing"
      transcript=""
    />,
  );
  expect(screen.queryByTestId("live-wave")).not.toBeInTheDocument();

  rerender(
    <FlashJourneyDock
      createdCount={0}
      error="Unavailable"
      onDismiss={vi.fn()}
      onRetry={onRetry}
      phase="failed"
      transcript="联系 Alex"
    />,
  );
  expect(screen.getByText("联系 Alex")).toHaveClass("flash-journey-transcript");
  expect(screen.getByRole("alert")).toHaveTextContent("Unavailable");
  expect(screen.queryByTestId("dock-dither")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Retry Flash" }));
  expect(onRetry).toHaveBeenCalledOnce();
});

it("lets the operator dismiss Generated without affecting its result copy", () => {
  const onDismiss = vi.fn();
  render(
    <FlashJourneyDock
      createdCount={2}
      error={null}
      onDismiss={onDismiss}
      onRetry={vi.fn()}
      phase="created"
      transcript="联系 Alex"
    />,
  );

  expect(screen.getByRole("heading", { name: "Generated" })).toBeVisible();
  expect(screen.getByText("2 cards added")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  expect(onDismiss).toHaveBeenCalledOnce();
});
