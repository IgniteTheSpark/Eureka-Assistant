import type { FlashResponse } from "../../lib/types";

export type AssetDomain =
  | "todo"
  | "event"
  | "contact"
  | "idea"
  | "note"
  | "expense"
  | "generic";

export interface FlashAssetBatch {
  id: string;
  transcript: string;
  createdAt: number;
  cards: Array<Record<string, unknown>>;
}

export interface FlashAssetItem {
  id: string;
  batchId: string;
  batchOrder: number;
  createdAt: number;
  card: Record<string, unknown>;
}

const KNOWN_DOMAINS = new Set<AssetDomain>([
  "todo",
  "event",
  "contact",
  "idea",
  "note",
  "expense",
]);

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function cardType(card: Record<string, unknown>) {
  const nested = asRecord(card.card) ?? card;
  for (const key of ["card_type", "user_skill_name", "skill_name", "type"]) {
    const value = nested[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim().toLowerCase();
    }
  }
  return "";
}

export function assetDomain(card: Record<string, unknown>): AssetDomain {
  const type = cardType(card);
  if (type === "notes" || type === "misc") return "note";
  return KNOWN_DOMAINS.has(type as AssetDomain)
    ? (type as AssetDomain)
    : "generic";
}

export function normalizeFlashCards(
  result: FlashResponse,
): Array<Record<string, unknown>> {
  if (Array.isArray(result.cards) && result.cards.length) {
    return result.cards.filter((card) => asRecord(card) !== null);
  }

  if (Array.isArray(result.derived_assets) && result.derived_assets.length) {
    return result.derived_assets.flatMap((asset) => {
      const record = asRecord(asset);
      if (!record) return [];
      return [asRecord(record.card) ?? record];
    });
  }

  const fallback = result.summary?.trim() || result.reply?.trim();
  return fallback
    ? [{ card_type: "note", content: fallback }]
    : [];
}

export function createFlashAssetBatch(
  transcript: string,
  result: FlashResponse,
  id: string,
  createdAt: number,
): FlashAssetBatch {
  return {
    id,
    transcript,
    createdAt,
    cards: normalizeFlashCards(result),
  };
}

export function flattenFlashAssetBatches(
  batches: FlashAssetBatch[],
): FlashAssetItem[] {
  return batches.flatMap((batch) =>
    batch.cards.map((card, batchOrder) => ({
      id: `${batch.id}-${batchOrder}`,
      batchId: batch.id,
      batchOrder,
      createdAt: batch.createdAt,
      card,
    })),
  );
}
