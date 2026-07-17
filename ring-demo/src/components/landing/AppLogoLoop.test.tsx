import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { AppLogoLoop } from "./AppLogoLoop";

describe("AppLogoLoop", () => {
  it("renders two accessible logo rows moving in opposite directions", () => {
    const { container } = render(
      <AppLogoLoop
        rows={[
          [
            {
              alt: "Codex",
              kind: "codex",
              name: "Codex",
              src: "/logos/codex.svg",
            },
            { name: "钉钉", kind: "dingtalk" },
          ],
          [
            { name: "GitHub", kind: "github" },
            { name: "and even more", kind: "more" },
          ],
        ]}
      />,
    );

    expect(screen.getAllByRole("list", { name: /示例连接软件第/ })).toHaveLength(2);
    expect(screen.getByRole("listitem", { name: "Codex" })).toBeInTheDocument();
    expect(screen.getByRole("listitem", { name: "钉钉" })).toBeInTheDocument();
    expect(screen.getByRole("listitem", { name: "and even more" })).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Codex" })).toHaveAttribute(
      "src",
      "/logos/codex.svg",
    );
    expect(screen.getByRole("img", { name: "Codex" })).toHaveClass("app-logo-image");
    expect(screen.getByRole("img", { name: "Codex" }).parentElement).toHaveClass(
      "app-logo-item",
    );
    expect(screen.getByRole("img", { name: "Codex" }).parentElement).not.toHaveClass(
      "app-logo-mark",
    );
    expect(container.querySelectorAll(".app-logo-row")).toHaveLength(2);
    expect(container.querySelector(".app-logo-row-reverse")).toBeInTheDocument();
    expect(container.querySelectorAll(".app-logo-set[aria-hidden='true']")).toHaveLength(2);
  });
});
