import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ScrollFloatText } from "./ScrollFloatText";

describe("ScrollFloatText", () => {
  it("keeps one accessible heading while exposing visual character spans", () => {
    const { container } = render(
      <ScrollFloatText as="h2" id="float-title" text="录音只是开始。" />,
    );

    expect(
      screen.getByRole("heading", { name: "录音只是开始。" }),
    ).toBeInTheDocument();
    expect(container.querySelectorAll(".scroll-float-char")).toHaveLength(7);
    expect(container.querySelector(".scroll-float-visual")).toHaveAttribute(
      "aria-hidden",
      "true",
    );
    expect(container.querySelector("#float-title")).toHaveAttribute(
      "data-scroll-float",
      "scrub",
    );
  });
});
