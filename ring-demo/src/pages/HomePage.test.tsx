import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

import { HomePage } from "./HomePage";

it("presents a Chinese product story without local demo controls or route links", async () => {
  const { container } = render(
    <MemoryRouter
      future={{ v7_relativeSplatPath: true, v7_startTransition: true }}
    >
      <HomePage />
    </MemoryRouter>,
  );

  expect(
    await screen.findByRole("img", { name: /eureka ring product/i }),
  ).toBeInTheDocument();
  expect(
    screen.getByTestId("living-ring-stage"),
  ).toHaveAttribute("data-focused-mode", "neutral");
  expect(screen.getByTestId("living-ring-stage")).not.toHaveAttribute(
    "data-scene-state",
  );
  expect(
    screen.getByRole("region", { name: /一枚戒指 · 两种智能体验/ }),
  ).toBeInTheDocument();
  expect(
    container.querySelector(".mode-title-line-primary"),
  ).toHaveTextContent("一枚戒指");
  expect(
    container.querySelector(".mode-title-line-secondary"),
  ).toHaveTextContent("两种智能体验");
  expect(container.querySelector(".mode-ring-corridor")).toBeInTheDocument();
  expect(container.querySelector(".hero-prism-backdrop")).not.toBeInTheDocument();
  expect(container.querySelector(".mode-soft-aurora")).not.toBeInTheDocument();
  expect(container.querySelectorAll(".mode-thesis .decrypted-text")).toHaveLength(2);
  expect(
    container.querySelector('.decrypted-text[aria-label="把一句话变成可继续使用的资产。"]'),
  ).toBeInTheDocument();
  expect(
    container.querySelector('.decrypted-text[aria-label="让声音直接进入正在使用的工具。"]'),
  ).toBeInTheDocument();
  expect(
    container.querySelector('[data-ring-chapter="mode-bridge"]'),
  ).toBeInTheDocument();
  expect(container.querySelector("#hero-title.scroll-float-text")).not.toBeInTheDocument();
  expect(
    container.querySelector("#modes-title.scroll-float-text[data-scroll-float='scrub']"),
  ).toBeInTheDocument();
  expect(screen.getByText("随身的个人智能入口")).toBeInTheDocument();
  expect(container.querySelectorAll("#hero-title .shuffle-text")).toHaveLength(2);
  expect(
    container.querySelector(
      '#hero-title .shuffle-text[aria-label="智能"]',
    ),
  ).toBeInTheDocument();
  expect(
    container.querySelector(
      '#hero-title .shuffle-text[aria-label="触手可及"]',
    ),
  ).toBeInTheDocument();
  expect(container.querySelector(".hero-lede")).toHaveTextContent(
    "一枚连接个人智能的戒指。捕捉转瞬即逝的想法，也让声音成为操作电脑的方式。",
  );
  expect(container.querySelector(".hero-lede .shuffle-text")).not.toBeInTheDocument();
  expect(screen.queryByText("EUREKA RING · 个人智能入口")).not.toBeInTheDocument();
  expect(screen.queryByText(/01\s*内测产品/)).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "向下探索" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "申请内测" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: /准备好时，再连接戒指/ })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /扫描戒指/i })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: /进入 flash/i })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: /进入 vibe/i })).not.toBeInTheDocument();
  expect(screen.queryByTestId("mode-scene-stage")).not.toBeInTheDocument();
  expect(
    screen.getByAltText("驾驶途中用戒指捕捉闪念"),
  ).toHaveAttribute("src", "/scenes/flash-driving-clean.webp");
  expect(
    screen.getByAltText("在 Codex 前用戒指发出指令"),
  ).toHaveAttribute("src", "/scenes/vibe-office-clean.webp");
  expect(container.querySelector(".mode-fields-backdrop")).not.toBeInTheDocument();

});
