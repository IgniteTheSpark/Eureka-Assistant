import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

import { SetupPage } from "./SetupPage";

const authResult = {
  ok: true,
  token: "jwt",
  user: { id: "1", email: "demo@example.com" },
};

beforeEach(() => localStorage.clear());

it.each([
  ["Sign in", "login"],
  ["Create account", "register"],
] as const)("stores a token after %s and enters the demo", async (buttonName, method) => {
  const backendClient = {
    login: vi.fn().mockResolvedValue(authResult),
    register: vi.fn().mockResolvedValue(authResult),
  };
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/setup"]}
    >
      <Routes>
        <Route path="/setup" element={<SetupPage backendClient={backendClient} />} />
        <Route path="/" element={<h1>Demo home</h1>} />
      </Routes>
    </MemoryRouter>,
  );

  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "demo@example.com" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "secret1" } });
  fireEvent.click(screen.getByRole("button", { name: buttonName }));

  await waitFor(() => expect(screen.getByRole("heading", { name: "Demo home" })).toBeInTheDocument());
  expect(backendClient[method]).toHaveBeenCalledWith("demo@example.com", "secret1");
  expect(localStorage.getItem("eureka.authToken")).toBe("jwt");
});

it("keeps the form visible and reports an API error", async () => {
  const backendClient = {
    login: vi.fn().mockRejectedValue(new Error("邮箱或密码错误")),
    register: vi.fn(),
  };
  render(
    <MemoryRouter future={{ v7_relativeSplatPath: true, v7_startTransition: true }}>
      <SetupPage backendClient={backendClient} />
    </MemoryRouter>,
  );

  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "demo@example.com" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "wrongpw" } });
  fireEvent.click(screen.getByRole("button", { name: "Sign in" }));

  expect(await screen.findByRole("alert")).toHaveTextContent("邮箱或密码错误");
});
