import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

import { ApiError } from "../lib/backend-client";
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
      flash: vi.fn(),
      resetDemo: vi.fn().mockResolvedValue({ ok: true, deleted: {} }),
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
  expect(screen.getByRole("heading", { name: "Codex" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "DingTalk" })).toBeInTheDocument();
  await waitFor(() => expect(dependencies.ringClient.acquire).toHaveBeenCalledTimes(1));
});

it.each([
  ["home", "/"],
  ["Flash", "/flash"],
  ["Vibe", "/vibe"],
] as const)("weakly surfaces operator controls with the account email on %s", async (_page, path) => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={[path]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  const trigger = await screen.findByRole("button", { name: /operator controls/i });
  fireEvent.click(trigger);
  expect(screen.getByText("demo@example.com")).toBeInTheDocument();
});

it("clears an expired token and returns to setup when reset receives a 401", async () => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  dependencies.backendClient.resetDemo.mockRejectedValue(
    new ApiError(401, { detail: "Session expired" }),
  );
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  fireEvent.click(await screen.findByRole("button", { name: /operator controls/i }));
  fireEvent.click(screen.getByRole("button", { name: /reset demo data/i }));
  fireEvent.click(screen.getByRole("button", { name: /confirm reset/i }));

  expect(await screen.findByRole("heading", { name: "Set up your demo" })).toBeInTheDocument();
  expect(window.localStorage.getItem("eureka.authToken")).toBeNull();
});

it.each([
  ["server failure", new ApiError(503, { detail: "Backend unavailable" })],
  ["network failure", new TypeError("Network unavailable")],
] as const)("preserves the token on a %s and retries bootstrap", async (_label, failure) => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  dependencies.backendClient.me
    .mockRejectedValueOnce(failure)
    .mockResolvedValueOnce({
      ok: true,
      user: { id: "1", email: "demo@example.com" },
    });
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/flash"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(failure.message);
  expect(window.localStorage.getItem("eureka.authToken")).toBe("jwt");
  fireEvent.click(screen.getByRole("button", { name: "Retry authentication" }));

  expect(await screen.findByRole("heading", { name: "Flash Mode" })).toBeInTheDocument();
  expect(dependencies.backendClient.me).toHaveBeenCalledTimes(2);
});

it.each([401, 403])("clears an invalid token after a %s response", async (status) => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  dependencies.backendClient.me.mockRejectedValue(
    new ApiError(status, { detail: "Session expired" }),
  );
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/flash"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  expect(await screen.findByRole("heading", { name: "Set up your demo" })).toBeInTheDocument();
  expect(window.localStorage.getItem("eureka.authToken")).toBeNull();
});

it("renders a retry action when selecting the route mode fails", async () => {
  window.localStorage.setItem("eureka.authToken", "jwt");
  const dependencies = clients();
  dependencies.ringClient.setMode
    .mockRejectedValueOnce(new Error("Mode service unavailable"))
    .mockResolvedValueOnce({ ...snapshot, mode: "flash", generation: 2 });
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/flash"]}
    >
      <App {...dependencies} />
    </MemoryRouter>,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent("Mode service unavailable");
  fireEvent.click(screen.getByRole("button", { name: "Retry Ring session" }));

  await waitFor(() => expect(dependencies.ringClient.setMode).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(screen.queryByText("Mode service unavailable")).toBeNull());
});
