import { useState } from "react";
import useSWR, { useSWRConfig } from "swr";
import { Plus, X as XIcon } from "lucide-react";

import { AssetDetailDrawer } from "@/components/asset/AssetDetailDrawer";
import { AssetPickerSheet } from "@/components/chat/AssetPickerSheet";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { patchSessionContext } from "@/hooks/useSessions";
import { swrFetcher } from "@/lib/api";
import { buildCard } from "@/lib/render-spec";
import type {
  AssetsResponse, ContactsResponse, EventsResponse, FilesResponse,
} from "@/lib/types";
import type { AccentColor, CardData } from "@/lib/render-spec";

/**
 * SessionTopicBar — single-row "what this chat is about" bar (RV1).
 *
 * Merges the old SubjectBanner (top row "🎯 主语 + entity card") and
 * ContextChipRail (next row "✨ 上下文 + chips + + 添加资产") into ONE
 * horizontal chip row:
 *
 *   ┌────────────────────────────────────────────────────┐
 *   │ [👤 Kevin (subject, brand ring)] · [📝 idea ×]    │
 *   │  [📅 团建 ×]  [+ 添加资产]                          │
 *   └────────────────────────────────────────────────────┘
 *
 * Distinction:
 *   - Subject chip: brand-blue ring + slightly heavier weight + no × button
 *     (subject is permanent for the session — change subject = different
 *     session). Tap → AssetDetailDrawer of the subject entity.
 *   - Context chips: regular accent tint per skill + × to remove. Tap →
 *     AssetDetailDrawer of the context asset.
 *   - 「+ 添加资产」: dashed border at the end, opens AssetPickerSheet.
 *
 * Subject sources (exactly one non-null determines it):
 *   contact_id (Kevin) | event_id (会议) | file_id (录音) |
 *   subject_asset_id (any asset)
 *
 * General-chat sessions (no subject FK) render just the context chips +
 * add button — the bar shrinks to "just additive context".
 */

interface SessionTopicBarProps {
  contactId?:        string | null;
  eventId?:          string | null;
  fileId?:           string | null;
  subjectAssetId?:   string | null;
  /** Current session's context_asset_ids (M2.2) */
  contextAssetIds:   string[];
  /** Session id — needed to patch context. null disables add/remove. */
  sessionId:         string | null;
}

interface ChipData {
  id:        string;
  icon:      string;
  accent:    AccentColor;
  title:     string;
  subtitle?: string;
  payload:   Record<string, unknown>;
  cardType:  string;
  displayName: string;
  sourceSessionId: string | null;
  /** Subject chips render heavier; context chips are subtler + removable. */
  isSubject: boolean;
}

export function SessionTopicBar({
  contactId, eventId, fileId, subjectAssetId,
  contextAssetIds, sessionId,
}: SessionTopicBarProps) {
  const { bySkill } = useSkillRegistry();
  const { mutate } = useSWRConfig();
  const [openChip,   setOpenChip]   = useState<ChipData | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [busy,       setBusy]       = useState(false);

  // ── Fetch any/all data sources lazily (SWR keys are null when not needed). ─
  const contactsSWR = useSWR<ContactsResponse>(contactId      ? "/api/contacts"          : null, swrFetcher);
  const eventsSWR   = useSWR<EventsResponse>(eventId          ? "/api/events"            : null, swrFetcher);
  const filesSWR    = useSWR<FilesResponse>(fileId            ? "/api/files"             : null, swrFetcher);
  const assetsSWR   = useSWR<AssetsResponse>(
    (subjectAssetId || contextAssetIds.length > 0) ? "/api/assets?limit=500" : null,
    swrFetcher,
  );

  // ── Build subject chip ────────────────────────────────────────────────
  const subject = buildSubjectChip({
    contactId, eventId, fileId, subjectAssetId,
    contactsSWR: contactsSWR.data, eventsSWR: eventsSWR.data,
    filesSWR: filesSWR.data, assetsSWR: assetsSWR.data, bySkill,
  });

  // ── Build context chips ───────────────────────────────────────────────
  const allAssets = assetsSWR.data?.assets ?? [];
  const contextChips: ChipData[] = contextAssetIds
    .map((id) => allAssets.find((a) => a.id === id))
    .filter((a): a is NonNullable<typeof a> => a != null)
    .map((a) => {
      const skill = bySkill.get(a.user_skill_name);
      const p = a.payload as { content?: unknown; title?: unknown; name?: unknown };
      return {
        id:        a.id,
        icon:      skill?.render_spec?.icon ?? "•",
        accent:    (skill?.render_spec?.accent_color ?? "gray") as AccentColor,
        title:     String(p.content ?? p.title ?? p.name ?? a.user_skill_name),
        payload:   a.payload,
        cardType:  a.user_skill_name,
        displayName: skill?.display_name ?? a.user_skill_name,
        sourceSessionId: a.session_id,
        isSubject: false,
      };
    });

  async function handleAdd(ids: string[]) {
    if (!sessionId) return;
    setBusy(true);
    try {
      await patchSessionContext(sessionId, { add: ids });
      await mutate(`/api/sessions/${sessionId}`);
    } finally {
      setBusy(false);
      setPickerOpen(false);
    }
  }

  async function handleRemove(id: string) {
    if (!sessionId || busy) return;
    setBusy(true);
    try {
      await patchSessionContext(sessionId, { remove: [id] });
      await mutate(`/api/sessions/${sessionId}`);
    } finally {
      setBusy(false);
    }
  }

  // Render even when there's nothing — the 「+ 添加资产」 button stays
  // accessible so a fresh chat can grow context.
  const hasAnything = subject != null || contextChips.length > 0 || sessionId != null;
  if (!hasAnything) return null;

  // Build the card data needed by AssetDetailDrawer when a chip is tapped.
  const openCard: CardData | null = openChip
    ? buildCard({
        payload: openChip.payload,
        spec: bySkill.get(openChip.cardType)?.render_spec ?? null,
        assetId: openChip.id,
        cardType: openChip.cardType,
        displayName: openChip.displayName,
      })
    : null;

  return (
    <>
      <div
        className={[
          "border-b border-eu-rule bg-eu-bg/60 backdrop-blur",
          "px-eu-md py-eu-sm flex items-center gap-eu-sm",
          "overflow-x-auto eu-noscroll",
        ].join(" ")}
      >
        {subject && <SubjectChip chip={subject} onOpen={() => setOpenChip(subject)} />}
        {/* Subtle separator between subject and context (only when both exist) */}
        {subject && contextChips.length > 0 && (
          <span className="shrink-0 text-eu-text-lo text-eu-sm select-none">·</span>
        )}
        {contextChips.map((c) => (
          <ContextChip
            key={c.id}
            chip={c}
            onOpen={() => setOpenChip(c)}
            onRemove={sessionId ? () => handleRemove(c.id) : undefined}
            busy={busy}
          />
        ))}
        {sessionId && (
          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            disabled={busy}
            className={[
              "shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-eu-full",
              "border border-dashed border-eu-border text-eu-text-mid text-eu-sm",
              "hover:bg-eu-surface-hover hover:text-eu-text-hi hover:border-eu-border-strong",
              "active:scale-95 disabled:opacity-50",
              "transition-all duration-eu-fast",
            ].join(" ")}
          >
            <Plus size={12} strokeWidth={2} />
            添加资产
          </button>
        )}
      </div>

      {openCard && openChip && (
        <AssetDetailDrawer
          card={openCard}
          payload={openChip.payload}
          sourceSessionId={openChip.sourceSessionId}
          onClose={() => setOpenChip(null)}
        />
      )}

      {pickerOpen && (
        <AssetPickerSheet
          onConfirm={handleAdd}
          onClose={() => setPickerOpen(false)}
          excludeIds={[
            ...contextAssetIds,
            ...(subjectAssetId ? [subjectAssetId] : []),
          ]}
        />
      )}
    </>
  );
}

/* ── Subject chip (brand-ring, heavier) ─────────────────────────────── */

function SubjectChip({ chip, onOpen }: { chip: ChipData; onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className={[
        "shrink-0 inline-flex items-center gap-1.5",
        "px-2.5 py-1 rounded-eu-full",
        "bg-eu-brand-faint text-eu-text-hi font-medium",
        "border border-eu-brand-line",
        "shadow-[0_0_0_2px_rgba(111,158,255,0.18)]",
        "hover:brightness-110 active:scale-95",
        "transition-all duration-eu-fast",
        "max-w-[28ch]",
      ].join(" ")}
      title={chip.title}
    >
      <span className="font-mono shrink-0 text-eu-brand-hi">{chip.icon}</span>
      <span className="truncate text-eu-sm">{chip.title}</span>
    </button>
  );
}

/* ── Context chip (light tint, removable) ───────────────────────────── */

function ContextChip({
  chip, onOpen, onRemove, busy,
}: {
  chip: ChipData;
  onOpen: () => void;
  onRemove?: () => void;
  busy: boolean;
}) {
  return (
    <div
      className={[
        "shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-eu-full",
        ACCENT_CHIP[chip.accent],
        "border text-eu-sm",
        "hover:brightness-110",
        "transition-all duration-eu-fast",
        "max-w-[22ch]",
      ].join(" ")}
    >
      <button
        type="button"
        onClick={onOpen}
        className="inline-flex items-center gap-1.5 min-w-0 active:scale-95"
      >
        <span className="font-mono shrink-0">{chip.icon}</span>
        <span className="truncate">{chip.title}</span>
      </button>
      {onRemove && (
        <button
          type="button"
          aria-label="移除"
          onClick={onRemove}
          disabled={busy}
          className="shrink-0 ml-0.5 -mr-0.5 p-0.5 rounded-full hover:bg-white/10 disabled:opacity-50"
        >
          <XIcon size={11} strokeWidth={2} />
        </button>
      )}
    </div>
  );
}

/* ── Subject chip builder (M2.3 FK → ChipData) ──────────────────────── */

function buildSubjectChip(args: {
  contactId?: string | null; eventId?: string | null;
  fileId?: string | null; subjectAssetId?: string | null;
  contactsSWR?: ContactsResponse; eventsSWR?: EventsResponse;
  filesSWR?: FilesResponse; assetsSWR?: AssetsResponse;
  bySkill: ReturnType<typeof useSkillRegistry>["bySkill"];
}): ChipData | null {
  const { contactId, eventId, fileId, subjectAssetId,
          contactsSWR, eventsSWR, filesSWR, assetsSWR, bySkill } = args;
  if (contactId) {
    const c = contactsSWR?.contacts?.find((x) => x.id === contactId);
    if (!c) return null;
    return {
      id: c.id, icon: "👤", accent: "neutral", title: c.name,
      payload: c as unknown as Record<string, unknown>,
      cardType: "contact", displayName: c.name, sourceSessionId: null,
      isSubject: true,
    };
  }
  if (eventId) {
    const e = eventsSWR?.events?.find((x) => x.event_id === eventId);
    if (!e) return null;
    return {
      id: e.event_id, icon: "📅", accent: "purple", title: e.title,
      payload: e as unknown as Record<string, unknown>,
      cardType: "event", displayName: e.title, sourceSessionId: null,
      isSubject: true,
    };
  }
  if (fileId) {
    const f = filesSWR?.files?.find((x) => x.id === fileId);
    if (!f) return null;
    const label = f.source_tag === "flash" ? "🎙 闪念录音"
                : f.source_tag === "meeting" ? "📁 会议录音" : "📎 文件";
    return {
      id: f.id, icon: "📎", accent: "gray", title: label,
      payload: f as unknown as Record<string, unknown>,
      cardType: "file", displayName: label, sourceSessionId: null,
      isSubject: true,
    };
  }
  if (subjectAssetId) {
    const a = assetsSWR?.assets?.find((x) => x.id === subjectAssetId);
    if (!a) return null;
    const skill = bySkill.get(a.user_skill_name);
    const p = a.payload as { content?: unknown; title?: unknown; name?: unknown };
    return {
      id: a.id,
      icon: skill?.render_spec?.icon ?? "•",
      accent: (skill?.render_spec?.accent_color ?? "gray") as AccentColor,
      title: String(p.content ?? p.title ?? p.name ?? a.user_skill_name),
      payload: a.payload,
      cardType: a.user_skill_name,
      displayName: skill?.display_name ?? a.user_skill_name,
      sourceSessionId: a.session_id,
      isSubject: true,
    };
  }
  return null;
}

/* ── Accent classes (same palette as old ContextChipRail) ───────────── */

const ACCENT_CHIP: Record<string, string> = {
  blue:    "bg-eu-accent-blue-bg text-eu-accent-blue-fg border-eu-accent-blue-edge",
  amber:   "bg-eu-accent-amber-bg text-eu-accent-amber-fg border-eu-accent-amber-edge",
  green:   "bg-eu-accent-green-bg text-eu-accent-green-fg border-eu-accent-green-edge",
  red:     "bg-eu-accent-red-bg text-eu-accent-red-fg border-eu-accent-red-edge",
  purple:  "bg-eu-accent-purple-bg text-eu-accent-purple-fg border-eu-accent-purple-edge",
  gray:    "bg-eu-accent-gray-bg text-eu-accent-gray-fg border-eu-accent-gray-edge",
  neutral: "bg-eu-accent-neutral-bg text-eu-accent-neutral-fg border-eu-accent-neutral-edge",
};
