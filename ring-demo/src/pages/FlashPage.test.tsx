import "@testing-library/jest-dom/vitest";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import type {
  DemoSnapshot,
  FlashResponse,
  RingConnectionSnapshot,
  RingEvent,
} from "../lib/types";
import { DemoProvider, useDemo } from "../state/demo-store";
import { FlashPage } from "./FlashPage";

vi.mock("../components/Dither", () => ({
  Dither: () => <div data-testid="dither-canvas" />,
}));

const connection: RingConnectionSnapshot = {
  status: "connected",
  connected: true,
  device: { address: "ring-id", name: "BCL60392D5" },
  devices: [],
  lastError: null,
};

const snapshot: DemoSnapshot = {
  sessionId: "tab-1",
  mode: "flash",
  generation: 2,
  connection,
  activeApp: null,
  mapping: null,
};

function testDependencies() {
  let emitEvent: ((event: RingEvent) => void) | undefined;
  let reconnect: (() => void) | undefined;
  const ringClient = {
    acquire: vi.fn().mockResolvedValue(snapshot),
    getStatus: vi.fn().mockResolvedValue(snapshot),
    getConnection: vi.fn().mockResolvedValue(connection),
    heartbeat: vi.fn().mockResolvedValue({ ok: true }),
    release: vi.fn().mockResolvedValue({ ok: true }),
    releaseOnUnload: vi.fn(),
    setMode: vi.fn().mockResolvedValue(snapshot),
    subscribe: vi.fn((onEvent: (event: RingEvent) => void, onReconnect: () => void) => {
      emitEvent = onEvent;
      reconnect = onReconnect;
      return vi.fn();
    }),
    scan: vi.fn(),
    connect: vi.fn(),
    disconnect: vi.fn(),
  };
  const backendClient = {
    flash: vi.fn<() => Promise<FlashResponse>>(),
  };
  return {
    backendClient,
    emit(event: string, data: Record<string, unknown>) {
      act(() => emitEvent?.({ event, data }));
    },
    reconnect() {
      act(() => reconnect?.());
    },
    ringClient,
  };
}

function renderPage(dependencies: ReturnType<typeof testDependencies>) {
  return render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
    >
      <DemoProvider ringClient={dependencies.ringClient}>
        <FlashPage
          backendClient={dependencies.backendClient}
          ringClient={dependencies.ringClient}
        />
        <ResetHarness />
      </DemoProvider>
    </MemoryRouter>,
  );
}

function ResetHarness() {
  const demo = useDemo();
  return (
    <>
      <output data-testid="flash-processing">
        {demo.flashProcessing ? "processing" : "idle"}
      </output>
      <button onClick={demo.resetLocalExperience} type="button">
        Test local reset
      </button>
    </>
  );
}

function matchingData(text?: string) {
  return {
    sessionId: "tab-1",
    generation: 2,
    mode: "flash",
    ...(text === undefined ? {} : { text }),
  };
}

beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  vi.stubGlobal("crypto", { randomUUID: () => "tab-1" });
});

afterEach(() => {
  vi.useRealTimers();
});

it("shows the shared connected ring and follows real recording events", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  expect(await screen.findByText("BCL60392D5")).toBeVisible();

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.emit("recording.stopped", matchingData());
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Transcribing" })).toBeVisible();
});

it("shows the Dither capture field only while the ring is recording", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");
  expect(screen.queryByTestId("flash-capture-effect")).not.toBeInTheDocument();

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByTestId("flash-capture-effect")).toBeVisible();
  expect(screen.getByTestId("dither-canvas")).toBeVisible();
  expect(screen.getByRole("heading", { name: "Capturing" })).toBeVisible();

  dependencies.emit("recording.stopped", matchingData());
  expect(screen.queryByTestId("flash-capture-effect")).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Capturing" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Transcribing" })).toBeVisible();
});

it("starts Flash immediately and keeps Generated open until the operator closes it", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash.mockResolvedValue({
    ok: true,
    cards: [{ card_type: "contact", name: "Alex" }],
  });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");
  vi.useFakeTimers();

  dependencies.emit("transcript.ready", matchingData("联系 Alex"));

  expect(dependencies.backendClient.flash).toHaveBeenCalledWith("联系 Alex");
  expect(screen.getByText("联系 Alex")).toHaveClass("flash-journey-transcript");
  expect(screen.getByRole("heading", { name: "Transcribing" })).toBeVisible();

  await act(async () => vi.advanceTimersByTimeAsync(699));
  expect(
    screen.queryByRole("heading", { name: "Analyzing" }),
  ).not.toBeInTheDocument();

  await act(async () => vi.advanceTimersByTimeAsync(1));
  expect(
    screen.getByRole("heading", { name: "Analyzing" }),
  ).toBeVisible();
  expect(screen.getByText("联系 Alex")).toHaveClass("flash-journey-transcript");

  await act(async () => vi.advanceTimersByTimeAsync(249));
  expect(
    screen.getByRole("heading", { name: "Analyzing" }),
  ).toBeVisible();

  await act(async () => vi.advanceTimersByTimeAsync(1));
  expect(screen.getByRole("heading", { name: "Generated" })).toBeVisible();
  expect(screen.getByText("1 card added")).toBeVisible();
  expect(screen.getByText("Alex")).toBeVisible();

  await act(async () => vi.advanceTimersByTimeAsync(10_000));
  expect(screen.getByRole("heading", { name: "Generated" })).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  expect(screen.queryByLabelText("Flash capture progress")).not.toBeInTheDocument();
});

it("recovers its capture phase from Desktop snapshots after SSE reconnects", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.ringClient.getStatus.mockResolvedValueOnce({
    ...snapshot,
    recording: false,
    asrProcessing: true,
  });
  dependencies.reconnect();
  expect(
    await screen.findByRole("heading", { name: "Transcribing" }),
  ).toBeVisible();
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();
  dependencies.ringClient.getStatus.mockResolvedValueOnce({
    ...snapshot,
    recording: false,
    asrProcessing: false,
  });
  dependencies.reconnect();
  expect(await screen.findByText("Ready")).toBeVisible();
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();

  dependencies.ringClient.getStatus.mockResolvedValueOnce({
    ...snapshot,
    recording: true,
    asrProcessing: false,
  });
  dependencies.reconnect();
  expect(await screen.findByText("Recording")).toBeVisible();
});

it("submits one matching transcript and reveals returned cards", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash.mockResolvedValue({
    ok: true,
    summary: "已记录 2 项",
    cards: [
      { card_type: "todo", content: "准备展会" },
      { card_type: "idea", content: "做一个戒指 Demo" },
    ],
  });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("transcript.ready", matchingData("帮我准备展会"));

  expect(await screen.findByText("准备展会")).toBeVisible();
  expect(screen.getByText("做一个戒指 Demo")).toBeVisible();
  expect(dependencies.backendClient.flash).toHaveBeenCalledTimes(1);
  expect(dependencies.backendClient.flash).toHaveBeenCalledWith("帮我准备展会");
  expect(screen.getAllByRole("article")[0]).toHaveClass("card-stagger-1");
  expect(screen.getAllByRole("article")[1]).toHaveClass("card-stagger-2");
});

it("shares Flash processing state until the backend request settles", async () => {
  const dependencies = testDependencies();
  let resolveFlash:
    | ((response: FlashResponse) => void)
    | undefined;
  dependencies.backendClient.flash.mockImplementation(
    () => new Promise((resolve) => { resolveFlash = resolve; }),
  );
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("transcript.ready", matchingData("帮我准备展会"));

  await waitFor(() =>
    expect(screen.getByTestId("flash-processing")).toHaveTextContent("processing"),
  );
  resolveFlash?.({ ok: true, cards: [] });
  await waitFor(() =>
    expect(screen.getByTestId("flash-processing")).toHaveTextContent("idle"),
  );
});

it("rejects stale, foreign, non-Flash, empty, and duplicate transcripts", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash.mockResolvedValue({
    ok: true,
    cards: [{ card_type: "note", content: "唯一接受" }],
  });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("transcript.ready", { ...matchingData("stale"), generation: 1 });
  dependencies.emit("transcript.ready", { ...matchingData("foreign"), sessionId: "other-tab" });
  dependencies.emit("transcript.ready", { ...matchingData("wrong mode"), mode: "vibe" });
  dependencies.emit("transcript.ready", matchingData("   "));
  dependencies.emit("transcript.ready", matchingData("唯一接受"));
  dependencies.emit("transcript.ready", matchingData("唯一接受"));

  expect(await screen.findByText("唯一接受")).toBeVisible();
  expect(dependencies.backendClient.flash).toHaveBeenCalledTimes(1);
});

it("retains the transcript after backend failure and retries it", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash
    .mockRejectedValueOnce(new Error("Flash backend unavailable"))
    .mockResolvedValueOnce({
      ok: true,
      cards: [{ card_type: "todo", content: "准备展会" }],
    });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("transcript.ready", matchingData("帮我准备展会"));

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Flash backend unavailable",
  );
  expect(
    screen.getByRole("heading", { name: "Ready to retry" }),
  ).toBeVisible();
  expect(screen.queryByText("Captured")).not.toBeInTheDocument();
  expect(screen.getByText("帮我准备展会")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry Flash" }));

  expect(await screen.findByText("准备展会")).toBeVisible();
  expect(dependencies.backendClient.flash).toHaveBeenCalledTimes(2);
  expect(dependencies.backendClient.flash).toHaveBeenLastCalledWith(
    "帮我准备展会",
  );
});

it("uses derived asset cards and falls back to a 随记 for text-only results", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash
    .mockResolvedValueOnce({
      ok: true,
      cards: [],
      derived_assets: [
        {
          asset_id: "asset-1",
          card: { card_type: "expense", title: "展会物料", subtitle: "¥320" },
        },
      ],
    })
    .mockResolvedValueOnce({
      ok: true,
      summary: "已经帮你记下了",
      reply: "稍后可以继续整理",
      cards: [],
      derived_assets: [],
    });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("transcript.ready", matchingData("展会物料三百二"));
  expect(await screen.findByText("展会物料")).toBeVisible();

  dependencies.emit("recording.started", matchingData());
  dependencies.emit("transcript.ready", matchingData("随手记一下"));
  expect(await screen.findByText("随记")).toBeVisible();
  expect(screen.getByText("已经帮你记下了")).toBeVisible();
  expect(screen.getByTestId("asset-flash-2-0")).toBeVisible();
  expect(screen.getByTestId("asset-flash-1-0")).toBeVisible();
  expect(document.querySelector(".flash-asset-batch")).not.toBeInTheDocument();
  expect(screen.getAllByRole("article")).toHaveLength(2);
  await waitFor(() => expect(dependencies.backendClient.flash).toHaveBeenCalledTimes(2));
});

it("clears transcript and result without reconnecting the Ring", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash.mockResolvedValue({
    ok: true,
    cards: [{ card_type: "todo", content: "准备展会" }],
  });
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");
  dependencies.emit("transcript.ready", matchingData("帮我准备展会"));
  expect(await screen.findByText("准备展会")).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Test local reset" }));

  expect(screen.queryByText("帮我准备展会")).not.toBeInTheDocument();
  expect(screen.queryByText("准备展会")).not.toBeInTheDocument();
  expect(screen.getByText("BCL60392D5")).toBeVisible();
  expect(dependencies.ringClient.acquire).toHaveBeenCalledTimes(1);
  expect(dependencies.ringClient.release).not.toHaveBeenCalled();
});

it("clears a local Flash error without reconnecting the Ring", async () => {
  const dependencies = testDependencies();
  dependencies.backendClient.flash.mockRejectedValue(
    new Error("Flash backend unavailable"),
  );
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");
  dependencies.emit("transcript.ready", matchingData("帮我准备展会"));
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Flash backend unavailable",
  );

  fireEvent.click(screen.getByRole("button", { name: "Test local reset" }));

  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  expect(screen.queryByText("帮我准备展会")).not.toBeInTheDocument();
  expect(screen.getByText("BCL60392D5")).toBeVisible();
  expect(dependencies.ringClient.acquire).toHaveBeenCalledTimes(1);
});
