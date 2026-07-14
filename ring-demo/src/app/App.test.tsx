import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

import type { DemoSnapshot, RingConnectionSnapshot } from "../lib/types";
import { App } from "./App";

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

function clients() {
  return {
    backendClient: {
      me: vi.fn().mockResolvedValue({ ok: true, user: { id: "1", email: "demo@example.com" } }),
      login: vi.fn(),
      register: vi.fn(),
    },
    ringClient: {
      acquire: vi.fn().mockResolvedValue(snapshot),
      getStatus: vi.fn().mockResolvedValue(snapshot),
      getConnection: vi.fn().mockResolvedValue(connection),
      heartbeat: vi.fn().mockResolvedValue({ ok: true }),
      release: vi.fn().mockResolvedValue({ ok: true }),
      releaseOnUnload: vi.fn(),
      setMode: vi.fn().mockResolvedValue(snapshot),
      subscribe: vi.fn(() => vi.fn()),
      scan: vi.fn(),
      connect: vi.fn(),
      disconnect: vi.fn(),
    },
  };
}

beforeEach(() => {
  window.localStorage.clear();
  window.sessionStorage.clear();
  vi.stubGlobal("crypto", { randomUUID: () => "tab-1" });
});

it("redirects an unauthenticated demo route to setup", async () => {
  const dependencies = clients();
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/flash"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  expect(await screen.findByRole("heading", { name: "Set up your demo" })).toBeInTheDocument();
  expect(dependencies.backendClient.me).not.toHaveBeenCalled();
});

it("keeps the connected ring state while switching between Flash and Vibe", async () => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/flash"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  expect(await screen.findByRole("heading", { name: "Flash Mode" })).toBeInTheDocument();
  expect(await screen.findByText("BCL60392D5")).toBeInTheDocument();
  expect(
    dependencies.ringClient.acquire.mock.invocationCallOrder[0],
  ).toBeLessThan(dependencies.ringClient.setMode.mock.invocationCallOrder[0] ?? 0);
  fireEvent.click(screen.getByRole("link", { name: "Vibe" }));
  expect(await screen.findByRole("heading", { name: "Vibe Mode" })).toBeInTheDocument();
  expect(screen.getByText("BCL60392D5")).toBeInTheDocument();
  await waitFor(() => expect(dependencies.ringClient.acquire).toHaveBeenCalledTimes(1));
});
