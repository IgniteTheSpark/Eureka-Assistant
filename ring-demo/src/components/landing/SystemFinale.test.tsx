import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { SystemFinale } from "./SystemFinale";

describe("SystemFinale", () => {
  it("summarizes the product as a bidirectional personal intelligence loop", () => {
    const { container } = render(<SystemFinale />);

    expect(
      screen.getByRole("heading", {
        name: "不是把助手缩小 · 是让智能始终在手边",
      }),
    ).toBeInTheDocument();
    [
      "Eureka Ring",
      "电脑或手机",
      "个人智能",
      "应用、AI 与资产",
      "触觉反馈",
    ].forEach((label) => expect(screen.getByText(label)).toBeInTheDocument());
    expect(container.querySelector(".system-drop-flow")).toBeInTheDocument();
    expect(container.querySelectorAll(".system-drop-node")).toHaveLength(5);
    const nodes = container.querySelectorAll(".system-drop-node");
    expect(nodes[0]).toHaveClass("system-drop-node-left");
    expect(nodes[1]).toHaveClass("system-drop-node-right");
    expect(nodes[2]).toHaveClass("system-drop-node-left");
    expect(nodes[3]).toHaveClass("system-drop-node-right");
    expect(nodes[4]).toHaveClass("system-drop-node-left");
    expect(container.querySelectorAll("[data-system-drop-step]")).toHaveLength(5);
    expect(container.querySelectorAll(".system-drop-signal")).toHaveLength(5);
    [
      "说 · 触",
      "连接 · 上下文",
      "理解 · 调用",
      "执行 · 沉淀",
      "状态 · 回响",
    ].forEach((signal) => expect(screen.getByText(signal)).toBeInTheDocument());
    expect(container.querySelector(".system-orbit")).not.toBeInTheDocument();
    expect(container.querySelector('[data-ring-chapter="system-start"]')).toBeInTheDocument();
    expect(container.querySelector('[data-ring-chapter="system-end"]')).toBeInTheDocument();
  });
});
