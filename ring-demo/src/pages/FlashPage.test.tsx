import "@testing-library/jest-dom/vitest";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

import type {
  DemoSnapshot,
  FlashResponse,
  RingConnectionSnapshot,
  RingEvent,
} from "../lib/types";
import { DemoProvider, useDemo } from "../state/demo-store";
import { FlashPage } from "./FlashPage";

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
  const ringClient = {
    acquire: vi.fn().mockResolvedValue(snapshot),
    getStatus: vi.fn().mockResolvedValue(snapshot),
    getConnection: vi.fn().mockResolvedValue(connection),
    heartbeat: vi.fn().mockResolvedValue({ ok: true }),
    release: vi.fn().mockResolvedValue({ ok: true }),
    releaseOnUnload: vi.fn(),
    setMode: vi.fn().mockResolvedValue(snapshot),
    subscribe: vi.fn((onEvent: (event: RingEvent) => void) => {
      emitEvent = onEvent;
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
    <button onClick={demo.resetLocalExperience} type="button">
      Test local reset
    </button>
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

it("shows the shared connected ring and follows real recording events", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  expect(await screen.findByText("BCL60392D5")).toBeVisible();

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.emit("recording.stopped", matchingData());
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();
  expect(screen.getByText("Transcribing")).toBeVisible();
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
  expect(screen.getByText("已记录 2 项")).toBeVisible();
  expect(dependencies.backendClient.flash).toHaveBeenCalledTimes(1);
  expect(dependencies.backendClient.flash).toHaveBeenCalledWith("帮我准备展会");
  expect(screen.getAllByRole("article")[0]).toHaveClass("card-stagger-1");
  expect(screen.getAllByRole("article")[1]).toHaveClass("card-stagger-2");
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
  expect(screen.getByText("Ready to retry")).toBeVisible();
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
