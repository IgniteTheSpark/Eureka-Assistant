import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { expect, it, vi } from "vitest";

import type { RingConnectionSnapshot } from "../lib/types";
import { RingConnection } from "./RingConnection";

const disconnected: RingConnectionSnapshot = {
  status: "disconnected",
  connected: false,
  device: null,
  devices: [],
  lastError: null,
};

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

it("keeps scan and connect pending from shared async connection status", async () => {
  const scan = deferred<Record<string, unknown>>();
  const connect = deferred<Record<string, unknown>>();
  const scanning = { ...disconnected, status: "scanning" };
  const ready = {
    ...disconnected,
    status: "ready",
    devices: [{ address: "ring-id", name: "BCL60392D5" }],
  };
  const connecting = {
    ...ready,
    status: "connecting",
    device: { address: "ring-id", name: "BCL60392D5" },
  };
  const connected = { ...connecting, status: "connected", connected: true };
  const ringClient = {
    scan: vi.fn(() => scan.promise),
    getConnection: vi.fn()
      .mockResolvedValueOnce(scanning)
      .mockResolvedValueOnce(connecting),
    connect: vi.fn(() => connect.promise),
    disconnect: vi.fn(),
  };
  const onConnectionChange = vi.fn();
  const view = render(
    <RingConnection
      connection={disconnected}
      onConnectionChange={onConnectionChange}
      ringClient={ringClient}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Scan for rings" }));
  expect(screen.getByRole("button", { name: "Scanning…" })).toBeDisabled();
  scan.resolve({ ok: true });
  await waitFor(() => expect(onConnectionChange).toHaveBeenCalledWith(scanning));

  view.rerender(
    <RingConnection connection={scanning} onConnectionChange={onConnectionChange} ringClient={ringClient} />,
  );
  expect(screen.getByRole("button", { name: "Scanning…" })).toBeDisabled();
  view.rerender(
    <RingConnection connection={ready} onConnectionChange={onConnectionChange} ringClient={ringClient} />,
  );
  fireEvent.click(screen.getByRole("button", { name: "BCL60392D5" }));
  expect(screen.getByRole("button", { name: "Connecting…" })).toBeDisabled();
  connect.resolve({ ok: true });
  await waitFor(() => expect(onConnectionChange).toHaveBeenCalledWith(connecting));

  view.rerender(
    <RingConnection connection={connecting} onConnectionChange={onConnectionChange} ringClient={ringClient} />,
  );
  expect(screen.getByRole("button", { name: "Connecting…" })).toBeDisabled();
  view.rerender(
    <RingConnection connection={connected} onConnectionChange={onConnectionChange} ringClient={ringClient} />,
  );
  expect(screen.getByRole("img", { name: "Connected ring" })).toBeInTheDocument();
  expect(screen.getByText("BCL60392D5")).toBeInTheDocument();
});

it("keeps a stable connected-ring visual with its device name", () => {
  const connected = {
    ...disconnected,
    status: "connected",
    connected: true,
    device: { address: "ring-id", name: "BCL60392D5" },
  } satisfies RingConnectionSnapshot;
  render(
    <RingConnection
      connection={connected}
      onConnectionChange={vi.fn()}
      ringClient={{
        scan: vi.fn(),
        getConnection: vi.fn(),
        connect: vi.fn(),
        disconnect: vi.fn(),
      }}
    />,
  );

  expect(screen.getByRole("img", { name: "Connected ring" })).toBeInTheDocument();
  expect(screen.getByText("BCL60392D5")).toBeInTheDocument();
  expect(screen.getByText("Connected")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Disconnect" })).toBeInTheDocument();
});
