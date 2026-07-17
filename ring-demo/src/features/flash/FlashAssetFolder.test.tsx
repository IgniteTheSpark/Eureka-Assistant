import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";

import type { FlashAssetBatch } from "./flash-assets";
import { FlashAssetFolder } from "./FlashAssetFolder";

const { scrollToStart } = vi.hoisted(() => ({ scrollToStart: vi.fn() }));

vi.mock("../../components/ScrollStack", async () => {
  const React = await import("react");
  return {
    ScrollStack: React.forwardRef(
      (
        { children }: { children: React.ReactNode },
        ref: React.ForwardedRef<{ scrollToStart(): void }>,
      ) => {
        React.useImperativeHandle(ref, () => ({ scrollToStart }));
        return <div data-testid="asset-scroll-stack">{children}</div>;
      },
    ),
    ScrollStackItem: ({ children }: { children: React.ReactNode }) => (
      <div data-testid="mock-scroll-stack-item">{children}</div>
    ),
  };
});

const oldBatch: FlashAssetBatch = {
  id: "old",
  transcript: "记下一个想法",
  createdAt: 100,
  cards: [{ card_type: "idea", domain: "灵感", content: "戒指演示" }],
};

const newBatch: FlashAssetBatch = {
  id: "new",
  transcript: "准备展会",
  createdAt: 200,
  cards: [
    { card_type: "todo", domain: "工作", content: "打印物料" },
    { card_type: "event", domain: "社交", title: "布展" },
  ],
};

const newerBatch: FlashAssetBatch = {
  id: "newer",
  transcript: "联系客户",
  createdAt: 300,
  cards: [{ card_type: "contact", name: "Alex" }],
};

it("shows a quiet empty state before the first batch", () => {
  render(<FlashAssetFolder batches={[]} />);

  expect(screen.getByText("Your assets will gather here.")).toBeVisible();
  expect(screen.queryByTestId("asset-scroll-stack")).not.toBeInTheDocument();
});

it("renders every asset as its own opaque stack item without a batch wrapper", () => {
  const { container } = render(
    <FlashAssetFolder batches={[newBatch, oldBatch]} />,
  );

  expect(screen.getAllByTestId("mock-scroll-stack-item")).toHaveLength(3);
  expect(screen.getByTestId("asset-new-0")).toHaveClass("flash-asset-entry");
  expect(screen.getByTestId("asset-new-1")).toHaveClass("flash-asset-entry");
  expect(screen.getByTestId("asset-old-0")).toHaveClass("flash-asset-entry");
  expect(container.querySelector(".flash-asset-batch")).not.toBeInTheDocument();
  expect(screen.queryByText("JUST NOW")).not.toBeInTheDocument();
  expect(screen.queryByText("EARLIER")).not.toBeInTheDocument();
  expect(screen.getAllByRole("article")).toHaveLength(3);
  expect(screen.getByText("3")).toBeVisible();
  expect(screen.getByLabelText("待办 card")).toHaveAttribute(
    "data-domain",
    "work",
  );
});

it("returns to the front only when the latest batch changes", () => {
  scrollToStart.mockClear();
  const { rerender } = render(
    <FlashAssetFolder batches={[newBatch, oldBatch]} />,
  );
  expect(scrollToStart).toHaveBeenCalledTimes(1);

  rerender(<FlashAssetFolder batches={[newBatch, oldBatch]} />);
  expect(scrollToStart).toHaveBeenCalledTimes(1);

  rerender(<FlashAssetFolder batches={[newerBatch, newBatch, oldBatch]} />);
  expect(scrollToStart).toHaveBeenCalledTimes(2);
});
