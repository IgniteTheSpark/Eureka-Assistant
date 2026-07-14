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

it("scans and connects a discovered ring", async () => {
  const ringClient = {
    scan: vi.fn().mockResolvedValue({ ok: true }),
    getConnection: vi.fn().mockResolvedValue({
      ...disconnected,
      devices: [{ address: "ring-id", name: "BCL60392D5" }],
    }),
    connect: vi.fn().mockResolvedValue({ ok: true }),
    disconnect: vi.fn(),
  };
  const onConnectionChange = vi.fn();
  render(
    <RingConnection
      connection={disconnected}
      onConnectionChange={onConnectionChange}
      ringClient={ringClient}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Scan for rings" }));
  const ring = await screen.findByRole("button", { name: /BCL60392D5/ });
  fireEvent.click(ring);

  await waitFor(() =>
    expect(ringClient.connect).toHaveBeenCalledWith({ address: "ring-id", name: "BCL60392D5" }),
  );
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
