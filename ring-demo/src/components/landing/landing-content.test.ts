import { describe, expect, it } from "vitest";

import { LANDING_CONTENT } from "./landing-content";

describe("LANDING_CONTENT", () => {
  it("defines every Chinese product chapter without unverified specs", () => {
    expect(LANDING_CONTENT.flash.examples).toHaveLength(4);
    expect(LANDING_CONTENT.senses).toHaveLength(3);
    expect(LANDING_CONTENT.system.nodes.map((node) => node.label)).toEqual([
      "Eureka Ring",
      "电脑或手机",
      "个人智能",
      "应用、AI 与资产",
      "触觉反馈",
    ]);
    expect(JSON.stringify(LANDING_CONTENT)).not.toMatch(
      /续航|防水|克重|价格/,
    );
  });

  it("keeps the two demo modes understandable in Chinese", () => {
    expect(LANDING_CONTENT.hero.title).toBe("智能 · 触手可及");
    expect(LANDING_CONTENT.modes.title).toBe("一枚戒指 · 两种智能体验");
    expect(LANDING_CONTENT.modes.flash.title).toBe("Flash Mode｜闪念");
    expect(LANDING_CONTENT.modes.vibe.title).toBe("Vibe Mode｜随声操控");
    expect(LANDING_CONTENT.community.title).toContain("第一批");
  });

  it("presents Codex and DingTalk as examples instead of a closed support list", () => {
    expect(JSON.stringify(LANDING_CONTENT.vibe)).toContain("软件示例");
    expect(JSON.stringify(LANDING_CONTENT.vibe)).toContain("持续扩展");
  });

  it("defines voice, seven gestures and three vibration patterns", () => {
    expect(LANDING_CONTENT.senses.map(({ id }) => id)).toEqual([
      "speak",
      "touch",
      "feel",
    ]);
    expect(JSON.stringify(LANDING_CONTENT.senses)).toContain("7 种手势交互");
    expect(JSON.stringify(LANDING_CONTENT.senses)).toContain("3 种震动反馈");
  });
});
