import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, expect, it, vi } from "vitest";

import { ApiError } from "../lib/backend-client";
import { OperatorControls } from "./OperatorControls";

function dependencies() {
  return {
    backendClient: {
      resetDemo: vi.fn().mockResolvedValue({
        ok: true as const,
        deleted: { captures: 2, cards: 3 },
      }),
    },
    resetLocalExperience: vi.fn(),
    onUnauthorized: vi.fn(),
    onManageAccount: vi.fn(),
    flashProcessing: false,
  };
}

beforeEach(() => vi.clearAllMocks());

it("opens operator account setup from the controls panel", () => {
  const props = dependencies();
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /manage demo account/i }));

  expect(props.onManageAccount).toHaveBeenCalledOnce();
});

it("requires confirmation before resetting the current demo account", async () => {
  const props = dependencies();
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  expect(screen.getByText("demo@example.com")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  expect(props.backendClient.resetDemo).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  await waitFor(() => expect(props.backendClient.resetDemo).toHaveBeenCalledTimes(1));
  expect(props.resetLocalExperience).toHaveBeenCalledTimes(1);
  expect(await screen.findByText(/5 demo records deleted/i)).toBeInTheDocument();
});

it("can cancel the explicit reset confirmation", () => {
  const props = dependencies();
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

  expect(screen.queryByRole("button", { name: /confirm reset/i })).not.toBeInTheDocument();
  expect(props.backendClient.resetDemo).not.toHaveBeenCalled();
});

it("moves focus into confirmation and restores it when cancelled", () => {
  const props = dependencies();
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  expect(screen.getByRole("button", { name: /confirm reset/i })).toHaveFocus();

  fireEvent.click(screen.getByRole("button", { name: /cancel/i }));
  expect(screen.getByRole("button", { name: /reset demo data/i })).toHaveFocus();
});

it("disables reset controls while the request is pending", async () => {
  let resolveReset: ((value: { ok: true; deleted: Record<string, number> }) => void) | undefined;
  const props = dependencies();
  props.backendClient.resetDemo.mockImplementation(
    () => new Promise((resolve) => { resolveReset = resolve; }),
  );
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(screen.getByRole("button", { name: /resetting demo data/i })).toBeDisabled();
  expect(screen.getByRole("button", { name: /cancel/i })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: /resetting demo data/i }));
  expect(props.backendClient.resetDemo).toHaveBeenCalledTimes(1);
  expect(props.resetLocalExperience).not.toHaveBeenCalled();

  resolveReset?.({ ok: true, deleted: {} });
  await waitFor(() => expect(props.resetLocalExperience).toHaveBeenCalledOnce());
});

it("disables reset while Flash is processing", () => {
  const props = dependencies();
  props.flashProcessing = true;
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));

  expect(screen.getByRole("button", { name: /reset demo data/i })).toBeDisabled();
  expect(screen.getByText(/wait for flash to finish/i)).toBeInTheDocument();
  expect(props.backendClient.resetDemo).not.toHaveBeenCalled();
});

it("blocks confirmation if Flash starts after confirmation opens", () => {
  const props = dependencies();
  const view = render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  view.rerender(
    <OperatorControls
      email="demo@example.com"
      {...props}
      flashProcessing
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));
  expect(screen.getByRole("button", { name: /confirm reset/i })).toBeDisabled();
  expect(props.backendClient.resetDemo).not.toHaveBeenCalled();
});

it("fails safely when a successful response has invalid deletion counts", async () => {
  const props = dependencies();
  props.backendClient.resetDemo.mockResolvedValue({
    ok: true,
    deleted: { captures: "2" },
  } as never);
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(await screen.findByRole("alert")).toHaveTextContent(/maintenance/i);
  expect(props.resetLocalExperience).not.toHaveBeenCalled();
});

it("preserves local state and shows a maintenance error when reset fails", async () => {
  const props = dependencies();
  props.backendClient.resetDemo.mockRejectedValue(new ApiError(503, { detail: "offline" }));
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(await screen.findByRole("alert")).toHaveTextContent(/maintenance/i);
  expect(props.resetLocalExperience).not.toHaveBeenCalled();
});

it("marks reset unavailable after a 404 without clearing local state", async () => {
  const props = dependencies();
  props.backendClient.resetDemo.mockRejectedValue(new ApiError(404, { detail: "Not found" }));
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(await screen.findByRole("alert")).toHaveTextContent(/not available/i);
  expect(screen.getByRole("button", { name: /reset demo data/i })).toBeDisabled();
  expect(props.resetLocalExperience).not.toHaveBeenCalled();
});

it("explains a 409 Flash conflict without clearing local state", async () => {
  const props = dependencies();
  props.backendClient.resetDemo.mockRejectedValue(
    new ApiError(409, { detail: "workspace operation in progress" }),
  );
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(await screen.findByRole("alert")).toHaveTextContent(
    /flash is still processing/i,
  );
  expect(props.resetLocalExperience).not.toHaveBeenCalled();
});

it("returns to authentication after a 401 without clearing local state", async () => {
  const props = dependencies();
  props.backendClient.resetDemo.mockRejectedValue(new ApiError(401, { detail: "Expired" }));
  render(<OperatorControls email="demo@example.com" {...props} />);

  fireEvent.click(screen.getByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  await waitFor(() => expect(props.onUnauthorized).toHaveBeenCalledOnce());
  expect(props.resetLocalExperience).not.toHaveBeenCalled();
});
