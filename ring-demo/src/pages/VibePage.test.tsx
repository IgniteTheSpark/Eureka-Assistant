import "@testing-library/jest-dom/vitest";
import { act, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

import type {
  DemoSnapshot,
  RingConnectionSnapshot,
  RingEvent,
} from "../lib/types";
import { DemoProvider } from "../state/demo-store";
import { VibePage } from "./VibePage";

const connection: RingConnectionSnapshot = {
  status: "connected",
  connected: true,
  device: { address: "ring-id", name: "BCL60392D5" },
  devices: [],
  lastError: null,
};

function testDependencies(overrides: Partial<DemoSnapshot> = {}) {
  let emitEvent: ((event: RingEvent) => void) | undefined;
  const snapshot: DemoSnapshot = {
    sessionId: "tab-1",
    mode: "vibe",
    generation: 2,
    connection,
    activeApp: null,
    mapping: null,
    ...overrides,
  };
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
  return {
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
        <VibePage ringClient={dependencies.ringClient} />
      </DemoProvider>
    </MemoryRouter>,
  );
}

function matchingData() {
  return { sessionId: "tab-1", generation: 2, mode: "vibe" };
}

beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  vi.stubGlobal("crypto", { randomUUID: () => "tab-1" });
});

it("shows the active Codex profile, current mapping, and shared ring visual", async () => {
  const dependencies = testDependencies({
    activeApp: "com.openai.codex",
    mapping: {
      double: "Voice",
      triple: "Enter",
      up: "Scroll up",
      down: "Scroll down",
    },
  });
  renderPage(dependencies);

  expect(await screen.findByText("Codex active")).toBeVisible();
  expect(screen.getByRole("heading", { name: "DingTalk" })).toBeVisible();
  expect(screen.getByText("Voice")).toBeVisible();
  expect(screen.getByText("Triple tap")).toBeVisible();
  expect(screen.getByRole("img", { name: "Connected ring" })).toBeVisible();
  expect(screen.getByText("BCL60392D5")).toBeVisible();
});

it("updates the active profile and mapping from Ring events", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  expect(
    await screen.findByText(
      "Open Codex or DingTalk to activate Ring controls.",
    ),
  ).toBeVisible();

  dependencies.emit("active_app.changed", {
    activeApp: "com.alibaba.DingTalkMac",
  });
  dependencies.emit("mapping.changed", {
    mapping: { double: "Voice", triple: "Enter" },
  });

  expect(screen.getByText("DingTalk active")).toBeVisible();
  expect(screen.getByText("Voice")).toBeVisible();
  expect(
    screen.queryByText("Open Codex or DingTalk to activate Ring controls."),
  ).not.toBeInTheDocument();
});

it("shows Recording only between matching live capture events", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("recording.started", {
    ...matchingData(),
    sessionId: "other-tab",
  });
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.emit("asr.started", matchingData());
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();

  dependencies.emit("recording.started", matchingData());
  dependencies.emit("recording.stopped", matchingData());
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();
});

it("clears Recording when the Vibe generation rolls over", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.emit("mode.changed", { mode: "vibe", generation: 3 });
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();

  dependencies.emit("recording.stopped", matchingData());
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();
});

it("clears Recording when the shared mode leaves Vibe", async () => {
  const dependencies = testDependencies();
  renderPage(dependencies);
  await screen.findByText("BCL60392D5");

  dependencies.emit("recording.started", matchingData());
  expect(screen.getByText("Recording")).toBeVisible();

  dependencies.emit("mode.changed", { mode: "idle", generation: 3 });
  expect(screen.queryByText("Recording")).not.toBeInTheDocument();
});

it("shows the unsupported-app prompt without inferred business outcomes", async () => {
  const dependencies = testDependencies({
    activeApp: "com.apple.Safari",
    mapping: {},
  });
  renderPage(dependencies);

  expect(
    await screen.findByText(
      "Open Codex or DingTalk to activate Ring controls.",
    ),
  ).toBeVisible();
  expect(screen.queryByText(/sent|success|failed/i)).not.toBeInTheDocument();
});

it.each(["constructor", "toString"])(
  "treats inherited object key %s as an unsupported app",
  async (activeApp) => {
    const dependencies = testDependencies({
      activeApp,
      mapping: { double: "Voice" },
    });
    renderPage(dependencies);

    expect(
      await screen.findByText(
        "Open Codex or DingTalk to activate Ring controls.",
      ),
    ).toBeVisible();
    expect(screen.queryByText("Voice")).not.toBeInTheDocument();
  },
);
