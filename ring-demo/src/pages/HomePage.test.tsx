import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

import { HomePage } from "./HomePage";

it("offers two large demo entries", () => {
  render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
    >
      <HomePage />
    </MemoryRouter>,
  );

  expect(screen.getByRole("link", { name: /explore flash/i })).toHaveAttribute(
    "href",
    "/flash",
  );
  expect(screen.getByRole("link", { name: /explore vibe/i })).toHaveAttribute(
    "href",
    "/vibe",
  );
});
