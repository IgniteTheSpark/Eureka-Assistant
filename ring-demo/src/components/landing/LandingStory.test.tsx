import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { CommunityCta } from "./CommunityCta";
import { LandingStory } from "./LandingStory";

describe("LandingStory", () => {
  it("renders the product story without redundant feature or hardware chapters", () => {
    const { container } = render(<LandingStory />);

    [
      "录音只是开始。",
      "不需要切换到另一块屏幕。",
      "不是把助手缩小 · 是让智能始终在手边",
      "说",
      "触",
      "感",
    ].forEach((title) => {
      expect(screen.getByRole("heading", { name: title })).toBeInTheDocument();
    });

    [
      "landing-flash-title",
      "landing-vibe-title",
      "landing-system-title",
      "landing-senses-title",
    ].forEach((id) => {
      expect(
        container.querySelector(`#${id}[data-scroll-float='scrub']`),
      ).toBeInTheDocument();
    });

    [
      "flash-intro",
      "flash-scene",
      "vibe-intro",
      "vibe-scene",
      "vibe-exit",
      "system-start",
      "system-end",
      "speak",
      "touch",
      "feel",
    ].forEach(
      (chapter) => {
        expect(
          container.querySelector(`[data-ring-chapter="${chapter}"]`),
        ).toBeInTheDocument();
      },
    );
  });

  it("places each scenario inside its matching mode chapter", () => {
    const { container } = render(<LandingStory />);

    expect(screen.getByText("一句自然表达")).toBeInTheDocument();
    expect(screen.getByText("形成资产")).toBeInTheDocument();
    expect(
      screen.getByRole("img", { name: "驾驶途中用戒指捕捉闪念" }),
    ).toHaveAttribute("src", "/scenes/flash-driving-clean.webp");
    expect(
      screen.getByRole("img", { name: "在 Codex 前用戒指发出指令" }),
    ).toHaveAttribute("src", "/scenes/vibe-office-clean.webp");
    expect(container.querySelector(".landing-system-rail")).not.toBeInTheDocument();
    expect(container.querySelectorAll(".sense-scene")).toHaveLength(3);
    expect(
      screen.getByRole("heading", { name: "说 · 触 · 感" }),
    ).toBeInTheDocument();
    expect(container.querySelector(".feature-bands")).not.toBeInTheDocument();
    expect(container.querySelector(".hardware-gallery")).not.toBeInTheDocument();
    expect(screen.getByText(/7 种手势交互/)).toBeInTheDocument();
    expect(screen.getByText(/3 种震动反馈/)).toBeInTheDocument();
    expect(
      container.querySelector(".landing-flash .landing-mode-grid"),
    ).toBeInTheDocument();
    expect(
      container.querySelector(".landing-flash .landing-section-copy"),
    ).toHaveClass("landing-mode-title");
    expect(
      container.querySelector(".landing-flash .landing-mode-ring-slot"),
    ).toHaveAttribute("data-ring-chapter", "flash-intro");
    expect(
      container.querySelector(".landing-flash .landing-scene"),
    ).toHaveClass("landing-mode-scene");
    expect(
      container.querySelector(".landing-flash .flash-pipeline"),
    ).toHaveClass("landing-mode-detail");
    expect(container.querySelector(".flash-example-stage")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "一句话，落到该去的地方。" })).toBeInTheDocument();
    expect(
      container.querySelector(".landing-vibe .landing-mode-ring-slot"),
    ).toHaveAttribute("data-ring-chapter", "vibe-intro");
    expect(
      container.querySelector(".landing-vibe .landing-section-copy"),
    ).toHaveClass("landing-mode-title");
    expect(
      container.querySelector(".landing-vibe .landing-scene"),
    ).toHaveClass("landing-mode-scene");
    expect(container.querySelector(".landing-vibe .vibe-ecosystem")).toHaveClass(
      "landing-mode-detail",
    );
    expect(container.querySelector(".landing-vibe .app-logo-loop")).toBeInTheDocument();
    expect(container.querySelector(".landing-vibe .vibe-targets")).not.toBeInTheDocument();
    expect(screen.getAllByRole("list", { name: /示例连接软件第/ })).toHaveLength(2);
    expect(
      screen.getByRole("listitem", { name: "and even more" }),
    ).toBeInTheDocument();
    expect(container.querySelector("[data-scroll-float='scrub']#landing-vibe-title")).toBeInTheDocument();
  });

  it("uses every supplied product logo and names NetEase Cloud Music explicitly", () => {
    render(<LandingStory />);

    const expectedLogos = [
      ["Codex", "/logos/codex-logo.jpeg"],
      ["Claude", "/logos/claude-logo.png"],
      ["钉钉", "/logos/dingding-logo.png"],
      ["飞书", "/logos/lark-logo.png"],
      ["VS Code", "/logos/vscode-logo.jpeg"],
      ["Cursor", "/logos/cursor-logo.png"],
      ["Trae", "/logos/trae-logo.png"],
      ["EurekaMind", "/logos/eurekamind-logo.png"],
      ["Notion", "/logos/notion-logo.png"],
      ["Slack", "/logos/slack-logo.jpeg"],
      ["微信", "/logos/wechat-logo.png"],
      ["Telegram", "/logos/telegram-logo.png"],
      ["Wisenote", "/logos/wisenote-logo.jpeg"],
      ["Chrome", "/logos/chrome logo.png"],
      ["Spotify", "/logos/spotify logo.png"],
      ["网易云音乐", "/logos/netease-logo.jpeg"],
    ] as const;

    expectedLogos.forEach(([name, src]) => {
      expect(screen.getByRole("listitem", { name })).toBeInTheDocument();
      expect(screen.getByRole("img", { name })).toHaveAttribute("src", src);
    });
  });

  it("moves the interaction demonstrations before the brand and system summary", () => {
    const { container } = render(<LandingStory />);
    const senses = container.querySelector(".landing-senses")!;
    const system = container.querySelector(".landing-system-finale")!;

    expect(
      senses.compareDocumentPosition(system) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(screen.getByText("想法或指令，直接说出来。")).toBeInTheDocument();
    expect(
      screen.getByText("同一个动作，在不同设备、应用和场景中承担不同含义。"),
    ).toBeInTheDocument();
    expect(
      screen.getByText("不用查看屏幕，也能感知状态与结果。"),
    ).toBeInTheDocument();
  });
});

describe("CommunityCta", () => {
  it("shows a local placeholder without embedding a missing QR document", () => {
    const { container } = render(<CommunityCta />);

    expect(
      screen.getByRole("heading", {
        name: "成为第一批使用 Eureka Ring 的人。",
      }),
    ).toBeInTheDocument();
    expect(screen.queryByText("扫码加入内测群")).not.toBeInTheDocument();
    expect(
      screen.queryByText("内测名额及开放时间以群内通知为准"),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /回到顶部/ })).not.toBeInTheDocument();
    expect(screen.queryByTestId("community-qr-object")).not.toBeInTheDocument();
    expect(screen.getByTestId("community-qr")).toHaveAttribute(
      "src",
      "/community/eureka-ring-beta-qr-placeholder.svg",
    );
    expect(
      container.querySelector(
        "#community-title.scroll-float-text[data-scroll-float='scrub']",
      ),
    ).toBeInTheDocument();
  });
});
