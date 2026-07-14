import "@testing-library/jest-dom/vitest";
import { act, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import { normalizeDemoSnapshot } from "../lib/ring-client";
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
      <output data-testid="generation">{demo.generation}</output>
      <output data-testid="active-app">{demo.activeApp}</output>
      <output data-testid="mapping">{JSON.stringify(demo.mapping)}</output>
      <output data-testid="device">{demo.connection.device?.name}</output>
      <output data-testid="events">{demo.events.length}</output>
      <button type="button" onClick={() => void demo.setMode("vibe")}>Vibe</button>
      <button type="button" onClick={() => void demo.setMode("flash")}>Flash</button>
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

it("ignores stale refresh and SSE mode generations", async () => {
  let resolveStatus: ((value: DemoSnapshot) => void) | undefined;
  const ring = fakeRingClient();
  ring.client.getStatus.mockImplementation(
    () => new Promise<DemoSnapshot>((resolve) => { resolveStatus = resolve; }),
  );
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() => expect(screen.getByTestId("generation")).toHaveTextContent("1"));

  act(() => ring.reconnect());
  act(() => ring.emit({
    event: "mode.changed",
    data: { mode: "flash", generation: 5 },
  }));
  expect(screen.getByTestId("mode")).toHaveTextContent("flash");
  expect(screen.getByTestId("generation")).toHaveTextContent("5");

  await act(async () => resolveStatus?.({ ...snapshot, mode: "vibe", generation: 2 }));
  expect(screen.getByTestId("mode")).toHaveTextContent("flash");
  expect(screen.getByTestId("generation")).toHaveTextContent("5");

  act(() => ring.emit({
    event: "snapshot",
    data: { sessionId: "tab-1", mode: "idle", generation: 4 },
  }));
  expect(screen.getByTestId("mode")).toHaveTextContent("flash");
});

it("preserves app and mapping when an equal-generation reconnect snapshot omits them", async () => {
  const ring = fakeRingClient();
  const richSnapshot = {
    ...snapshot,
    activeApp: "com.openai.codex",
    mapping: { double: "Voice", triple: "Enter" },
  } satisfies DemoSnapshot;
  ring.client.acquire.mockResolvedValue(richSnapshot);
  ring.client.getStatus.mockResolvedValue(
    normalizeDemoSnapshot({
      session_id: "tab-1",
      mode: "idle",
      generation: 1,
    }),
  );
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() =>
    expect(screen.getByTestId("active-app")).toHaveTextContent(
      "com.openai.codex",
    ),
  );

  act(() => ring.reconnect());
  await waitFor(() => expect(ring.client.getStatus).toHaveBeenCalledOnce());
  expect(screen.getByTestId("active-app")).toHaveTextContent("com.openai.codex");
  expect(screen.getByTestId("mapping")).toHaveTextContent(
    JSON.stringify(richSnapshot.mapping),
  );

  act(() => ring.emit({
    event: "snapshot",
    data: {
      session_id: "tab-1",
      mode: "idle",
      generation: 1,
      active_app: null,
      mapping: null,
    },
  }));
  expect(screen.getByTestId("active-app")).toBeEmptyDOMElement();
  expect(screen.getByTestId("mapping")).toHaveTextContent("null");
});

it("serializes rapid mode changes and only applies the latest response", async () => {
  const ring = fakeRingClient();
  let resolveFlash: ((value: DemoSnapshot) => void) | undefined;
  let resolveVibe: ((value: DemoSnapshot) => void) | undefined;
  ring.client.setMode
    .mockImplementationOnce(
      () => new Promise<DemoSnapshot>((resolve) => { resolveFlash = resolve; }),
    )
    .mockImplementationOnce(
      () => new Promise<DemoSnapshot>((resolve) => { resolveVibe = resolve; }),
    );
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));

  screen.getByRole("button", { name: "Flash" }).click();
  screen.getByRole("button", { name: "Vibe" }).click();
  await waitFor(() => expect(ring.client.setMode).toHaveBeenCalledTimes(1));

  await act(async () => resolveFlash?.({ ...snapshot, mode: "flash", generation: 2 }));
  expect(ring.client.setMode).toHaveBeenCalledTimes(2);
  expect(screen.getByTestId("mode")).toHaveTextContent("idle");
  expect(screen.getByTestId("generation")).toHaveTextContent("1");

  await act(async () => resolveVibe?.({ ...snapshot, mode: "vibe", generation: 3 }));
  expect(screen.getByTestId("mode")).toHaveTextContent("vibe");
  expect(screen.getByTestId("generation")).toHaveTextContent("3");
});

it("does not let a deferred setMode response overwrite a newer SSE generation", async () => {
  const ring = fakeRingClient();
  let resolveMode: ((value: DemoSnapshot) => void) | undefined;
  ring.client.setMode.mockImplementation(
    () => new Promise<DemoSnapshot>((resolve) => { resolveMode = resolve; }),
  );
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );
  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));

  screen.getByRole("button", { name: "Flash" }).click();
  await waitFor(() => expect(ring.client.setMode).toHaveBeenCalledOnce());
  act(() => ring.emit({
    event: "mode.changed",
    data: { mode: "vibe", generation: 5 },
  }));
  await act(async () => resolveMode?.({ ...snapshot, mode: "flash", generation: 2 }));

  expect(screen.getByTestId("mode")).toHaveTextContent("vibe");
  expect(screen.getByTestId("generation")).toHaveTextContent("5");
});

it("renders and retries a failed demo lease", async () => {
  const ring = fakeRingClient();
  ring.client.acquire
    .mockRejectedValueOnce(new Error("Ring Desktop offline"))
    .mockResolvedValueOnce(snapshot);
  render(
    <DemoProvider ringClient={ring.client}>
      <Harness />
    </DemoProvider>,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent("Ring Desktop offline");
  await act(async () => {
    screen.getByRole("button", { name: "Retry Ring session" }).click();
    await Promise.resolve();
  });

  await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
  expect(ring.client.acquire).toHaveBeenCalledTimes(2);
});
