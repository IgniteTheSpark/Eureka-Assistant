import "@testing-library/jest-dom/vitest";
import { act, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import type { DemoSnapshot, RingConnectionSnapshot, RingEvent } from "../lib/types";
import { DemoProvider, useDemo } from "./demo-store";

const connection: RingConnectionSnapshot = {
  status: "connected",
  connected: true,
  device: { address: "ring-id", name: "BCL60392D5" },
  devices: [],
  lastError: null,
};

const snapshot: DemoSnapshot = {
  sessionId: "tab-1",
  mode: "idle",
  generation: 1,
  connection,
  activeApp: null,
  mapping: null,
};

function Harness() {
  const demo = useDemo();
  return (
    <>
      <output data-testid="session">{demo.sessionId}</output>
      <output data-testid="status">{demo.ringStatus}</output>
      <output data-testid="mode">{demo.mode}</output>
      <output data-testid="device">{demo.connection.device?.name}</output>
      <output data-testid="events">{demo.events.length}</output>
      <button type="button" onClick={() => void demo.setMode("vibe")}>Vibe</button>
    </>
  );
}

function fakeRingClient() {
  let emit: ((event: RingEvent) => void) | undefined;
  let reconnect: (() => void) | undefined;
  return {
    client: {
      acquire: vi.fn().mockResolvedValue(snapshot),
      getStatus: vi.fn().mockResolvedValue(snapshot),
      getConnection: vi.fn().mockResolvedValue(connection),
      heartbeat: vi.fn().mockResolvedValue({ ok: true }),
      release: vi.fn().mockResolvedValue({ ok: true }),
      setMode: vi.fn().mockResolvedValue({ ...snapshot, mode: "vibe", generation: 2 }),
      subscribe: vi.fn((onEvent: (event: RingEvent) => void, onReconnect: () => void) => {
        emit = onEvent;
        reconnect = onReconnect;
        return vi.fn();
      }),
      releaseOnUnload: vi.fn(),
    },
    emit: (event: RingEvent) => emit?.(event),
    reconnect: () => reconnect?.(),
  };
}

beforeEach(() => {
  sessionStorage.clear();
  vi.useFakeTimers({ shouldAdvanceTime: true });
  vi.stubGlobal("crypto", { randomUUID: () => "tab-1" });
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

it("creates one tab session, acquires it, and heartbeats every three seconds", async () => {
  const ring = fakeRingClient();
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );

  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
  expect(ring.client.acquire).toHaveBeenCalledWith("tab-1");
  expect(sessionStorage.getItem("eureka.ringDemo.sessionId")).toBe("tab-1");

  await act(async () => vi.advanceTimersByTimeAsync(3_000));
  expect(ring.client.heartbeat).toHaveBeenCalledWith("tab-1");
});

it("applies SSE state and refreshes the snapshot when EventSource reconnects", async () => {
  const ring = fakeRingClient();
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));

  act(() => ring.emit({ event: "connection.changed", data: { ...connection, device: { address: "2", name: "New ring" } } }));
  expect(screen.getByTestId("device")).toHaveTextContent("New ring");
  expect(screen.getByTestId("events")).toHaveTextContent("1");

  act(() => ring.reconnect());
  await waitFor(() => expect(ring.client.getStatus).toHaveBeenCalledOnce());
});

it("changes mode through the shared provider and releases on unload", async () => {
  const ring = fakeRingClient();
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));

  screen.getByRole("button", { name: "Vibe" }).click();
  await waitFor(() => expect(screen.getByTestId("mode")).toHaveTextContent("vibe"));

  window.dispatchEvent(new Event("beforeunload"));
  expect(ring.client.releaseOnUnload).toHaveBeenCalledWith("tab-1");
});
