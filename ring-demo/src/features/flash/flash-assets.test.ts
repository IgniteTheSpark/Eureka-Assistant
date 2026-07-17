import { describe, expect, it } from "vitest";

import {
  assetDomain,
  createFlashAssetBatch,
  flattenFlashAssetBatches,
  normalizeFlashCards,
} from "./flash-assets";

describe("flash asset batches", () => {
  it("creates one ordered batch from every card in one response", () => {
    const batch = createFlashAssetBatch(
      "准备展会",
      {
        ok: true,
        cards: [
          { card_type: "todo", content: "打印物料" },
          { card_type: "event", title: "布展" },
        ],
      },
      "batch-1",
      100,
    );

    expect(batch).toMatchObject({
      id: "batch-1",
      transcript: "准备展会",
      createdAt: 100,
    });
    expect(batch.cards).toHaveLength(2);
    expect(batch.cards.map(assetDomain)).toEqual(["todo", "event"]);
  });

  it("unwraps derived assets when direct cards are absent", () => {
    expect(
      normalizeFlashCards({
        ok: true,
        cards: [],
        derived_assets: [
          {
            asset_id: "asset-1",
            card: { card_type: "expense", title: "展会物料" },
          },
        ],
      }),
    ).toEqual([{ card_type: "expense", title: "展会物料" }]);
  });

  it("creates a one-card note batch for a text-only response", () => {
    const batch = createFlashAssetBatch(
      "随手记一下",
      { ok: true, summary: "已经帮你记下了", cards: [] },
      "batch-2",
      200,
    );

    expect(batch.cards).toEqual([
      expect.objectContaining({
        card_type: "note",
        content: "已经帮你记下了",
      }),
    ]);
  });

  it("classifies nested and unknown cards without leaking arbitrary types", () => {
    expect(assetDomain({ card: { card_type: "contact" } })).toBe("contact");
    expect(assetDomain({ card_type: "book_note" })).toBe("generic");
  });

  it("flattens newest-first batches into stable individual asset items", () => {
    const oldBatch = createFlashAssetBatch(
      "旧闪念",
      { ok: true, cards: [{ card_type: "idea", content: "旧卡" }] },
      "old",
      100,
    );
    const newBatch = createFlashAssetBatch(
      "新闪念",
      {
        ok: true,
        cards: [
          { card_type: "todo", content: "新卡一" },
          { card_type: "event", title: "新卡二" },
        ],
      },
      "new",
      200,
    );

    expect(
      flattenFlashAssetBatches([newBatch, oldBatch]).map((item) => ({
        id: item.id,
        batchId: item.batchId,
        batchOrder: item.batchOrder,
        createdAt: item.createdAt,
      })),
    ).toEqual([
      { id: "new-0", batchId: "new", batchOrder: 0, createdAt: 200 },
      { id: "new-1", batchId: "new", batchOrder: 1, createdAt: 200 },
      { id: "old-0", batchId: "old", batchOrder: 0, createdAt: 100 },
    ]);
  });
});
