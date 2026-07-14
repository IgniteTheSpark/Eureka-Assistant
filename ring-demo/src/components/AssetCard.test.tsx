import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { expect, it } from "vitest";

import { AssetCard } from "./AssetCard";

it.each([
  ["todo", "待办", { content: "准备展会", due_date: "周五" }],
  ["idea", "灵感", { content: "做一个戒指 Demo" }],
  ["event", "日程", { title: "产品评审", location: "会议室 B" }],
  ["contact", "联系人", { name: "刘洋", company: "UReka" }],
  ["expense", "记账", { title: "展会物料", amount: "320" }],
  ["note", "随记", { content: "展台要保持简洁" }],
] as const)("renders the UReka %s card shape", (cardType, label, fields) => {
  render(<AssetCard card={{ card_type: cardType, ...fields }} />);
  const values = fields as Record<string, string>;

  expect(screen.getByText(label)).toBeVisible();
  expect(
    screen.getByText(
      String(values.content ?? values.title ?? values.name),
    ),
  ).toBeVisible();
});

it("uses prebuilt title, subtitle, and meta fields", () => {
  render(
    <AssetCard
      card={{
        card_type: "todo",
        title: "提交季度报告",
        subtitle: "周五截止",
        meta_fields: [{ field: "domain", value: "工作", format: "badge" }],
      }}
    />,
  );

  expect(screen.getByText("提交季度报告")).toBeVisible();
  expect(screen.getByText("周五截止")).toBeVisible();
  expect(screen.getByText("工作")).toBeVisible();
});

it("renders an unknown asset generically without exposing secret fields", () => {
  render(
    <AssetCard
      card={{
        card_type: "book_note",
        display_name: "读书笔记",
        payload: {
          book: "设计中的设计",
          quote: "让复杂自然消失",
          auth_token: "do-not-render",
        },
      }}
    />,
  );

  expect(screen.getByText("读书笔记")).toBeVisible();
  expect(screen.getByText(/设计中的设计/)).toBeVisible();
  expect(screen.getByText(/让复杂自然消失/)).toBeVisible();
  expect(screen.queryByText(/do-not-render/)).not.toBeInTheDocument();
});

it("adds a deterministic stagger class for multi-card reveals", () => {
  const { container } = render(
    <AssetCard card={{ card_type: "idea", content: "戒指 Demo" }} index={2} />,
  );

  expect(container.firstElementChild).toHaveClass("asset-card", "card-stagger-3");
});
