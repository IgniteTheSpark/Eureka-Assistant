import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { expect, it } from "vitest";

import { App } from "./App";

it("renders the public product landing", async () => {
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
      initialEntries={["/"]}
    >
      <App />
    </MemoryRouter>,
  );

  expect(
    await screen.findByRole("heading", { name: "智能 · 触手可及" }),
  ).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /扫描戒指/i })).not.toBeInTheDocument();
});

it.each(["/flash", "/vibe"])(
  "keeps the hidden demo route %s out of the public product",
  async (path) => {
    render(
      <MemoryRouter
        future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
        initialEntries={[path]}
      >
        <App />
      </MemoryRouter>,
    );

    expect(
      await screen.findByRole("heading", { name: "智能 · 触手可及" }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: /Flash Mode|Vibe Mode/ })).not.toBeInTheDocument();
  },
);

it.each(["/setup", "/operator/setup"])(
  "redirects the retired setup route %s to the public landing",
  async (path) => {
    render(
      <MemoryRouter
        future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
        initialEntries={[path]}
      >
        <App />
      </MemoryRouter>,
    );

    expect(
      await screen.findByRole("heading", { name: "智能 · 触手可及" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Operator account setup" }),
    ).not.toBeInTheDocument();
  },
);
