import { ArrowLeft, Trash2 } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import useSWR, { useSWRConfig } from "swr";

import { useAssets } from "@/hooks/useAssets";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useToggleTodo } from "@/hooks/useToggleTodo";
import { apiFetch, swrFetcher } from "@/lib/api";
import { buildCard } from "@/lib/render-spec";
import type {
  ContactsResponse, EventsResponse, FilesResponse,
} from "@/lib/types";

import { SkillCard } from "@/components/skill/SkillCard";
import { AssetDetailDrawer } from "@/components/asset/AssetDetailDrawer";

/**
 * CategoryDetail — drill-down list for one skill type.
 *
 * Driven by the URL param `:skillName`. For asset-backed skills
 * (todo/idea/notes/misc/expense/contact-as-asset) we hit /api/assets with
 * filter. For first-class entity types (event/file/contact) we hit their
 * dedicated endpoints and synthesize CardData inline using a hardcoded
 * "fake render_spec" that matches what we'd seed if they were skills.
 *
 * Tapping a card opens AssetDetailDrawer (M1: read-only).
 */
/** System / first-class skills the user can't delete from the UI. */
const PROTECTED_SKILLS = new Set([
  "event", "file", "contact", "external_ref", "qa",
  "todo", "idea", "notes", "expense", "misc",
]);

export function CategoryDetail() {
  const { skillName = "" } = useParams<{ skillName: string }>();
  const { bySkill } = useSkillRegistry();
  const navigate = useNavigate();
  const { mutate } = useSWRConfig();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [deleteState, setDeleteState] = useState<"idle" | "confirm" | "force-confirm" | "deleting">("idle");
  const toggleTodo = useToggleTodo();

  const skill = bySkill.get(skillName);
  const canDelete = !PROTECTED_SKILLS.has(skillName) && skill?.user_skill_id;

  // Determine data source for this skill.
  // contact: 真身 lives in /api/contacts (per Phase B v1.4); asset-skill is
  // only a timeline reference. Always read from contacts table for the
  // library view.
  const isEvent   = skillName === "event";
  const isFile    = skillName === "file";
  const isContact = skillName === "contact";

  const assetsHook = useAssets({
    skillName: !isEvent && !isFile && !isContact ? skillName : undefined,
    limit: 200,
  });

  const eventsSWR = useSWR<EventsResponse>(isEvent ? "/api/events" : null, swrFetcher);
  const filesSWR  = useSWR<FilesResponse>(isFile ? "/api/files" : null, swrFetcher);
  const contactsSWR = useSWR<ContactsResponse>(isContact ? "/api/contacts" : null, swrFetcher);

  const titleText = skill?.display_name ?? FALLBACK_LABEL[skillName] ?? skillName;

  // Build CardData list per source
  let cards: {
    id: string;
    data: ReturnType<typeof buildCard>;
    payload: Record<string, unknown>;
    sourceSessionId?: string | null;
  }[] = [];

  if (isEvent) {
    // Backend /api/events response uses `event_id` (not `id`) for the UUID.
    cards = (eventsSWR.data?.events ?? []).map((ev) => ({
      id: ev.event_id,
      payload: ev as unknown as Record<string, unknown>,
      data: buildCard({
        payload: ev as unknown as Record<string, unknown>,
        spec: {
          card_layout: "horizontal",
          icon: "📅",
          accent_color: "purple",
          primary_field: "title",
          secondary_field: "start_at",
          secondary_format: "relative_date",
          meta_fields: [{ field: "location" }],
        },
        assetId: ev.event_id,
        cardType: "event",
        displayName: "事件",
      }),
    }));
  } else if (isFile) {
    cards = (filesSWR.data?.files ?? []).map((f) => ({
      id: f.id,
      payload: f as unknown as Record<string, unknown>,
      data: buildCard({
        payload: { ...f, label: fileLabel(f) } as Record<string, unknown>,
        spec: {
          card_layout: "horizontal",
          icon: "📎",
          accent_color: "gray",
          primary_field: "label",
          secondary_field: "file_type",
          meta_fields: [
            { field: "asr_status" },
            { field: "asset_count", format: "badge" },
          ],
        },
        assetId: f.id,
        cardType: "file",
        displayName: "文件",
      }),
    }));
  } else if (isContact) {
    cards = (contactsSWR.data?.contacts ?? []).map((c) => ({
      id: c.id,
      payload: c as unknown as Record<string, unknown>,
      data: buildCard({
        payload: c as unknown as Record<string, unknown>,
        spec: {
          card_layout: "horizontal",
          icon: "👤",
          accent_color: "neutral",
          primary_field: "name",
          secondary_field: "company",
          meta_fields: [{ field: "title" }, { field: "phone" }],
        },
        assetId: c.id,
        cardType: "contact",
        displayName: "联系人",
      }),
    }));
  } else {
    cards = assetsHook.assets.map((a) => ({
      id: a.id,
      payload: a.payload,
      sourceSessionId: a.session_id,
      data: buildCard({
        payload: a.payload,
        spec: skill?.render_spec ?? null,
        assetId: a.id,
        cardType: skillName,
        displayName: titleText,
      }),
    }));
  }

  const loading = assetsHook.isLoading || eventsSWR.isLoading || filesSWR.isLoading || contactsSWR.isLoading;
  const empty = !loading && cards.length === 0;

  const selectedEntry =
    selectedId != null ? cards.find((c) => c.id === selectedId) ?? null : null;
  const selectedPayload = selectedEntry?.payload ?? null;
  const selectedCard    = selectedEntry?.data ?? null;
  const selectedSource  = selectedEntry?.sourceSessionId ?? null;

  async function handleDelete(force: boolean) {
    if (!skill?.user_skill_id) return;
    setDeleteState("deleting");
    try {
      const resp = await apiFetch<{ ok: boolean; deleted_assets?: number; error?: string }>(
        `/api/skills/${skill.user_skill_id}${force ? "?force=true" : ""}`,
        { method: "DELETE" },
      );
      if (!resp.ok && cards.length > 0 && !force) {
        // assets exist — surface the force confirmation
        setDeleteState("force-confirm");
        return;
      }
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/skills") || key.startsWith("/api/assets")
      ));
      navigate("/library");
    } catch (e) {
      // Network / server error — let the user retry from the same modal
      console.error("delete skill failed", e);
      setDeleteState("confirm");
    }
  }

  return (
    <div className="px-eu-md pt-eu-md">
      <div className="flex items-center gap-eu-sm mb-eu-md">
        <Link
          to="/library"
          className={[
            "h-8 w-8 rounded-eu-md flex items-center justify-center",
            "text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover",
            "transition-colors duration-eu-fast",
          ].join(" ")}
        >
          <ArrowLeft size={18} strokeWidth={1.75} />
        </Link>
        <h2 className="font-display text-eu-xl text-eu-text-hi tracking-tight">{titleText}</h2>
        <span className="font-mono text-eu-sm text-eu-text-lo">{cards.length}</span>
        {canDelete && (
          <button
            type="button"
            onClick={() => setDeleteState(cards.length > 0 ? "force-confirm" : "confirm")}
            aria-label="删除技能"
            title="删除这个技能"
            className={[
              "ml-auto h-7 w-7 rounded-eu-md flex items-center justify-center",
              "text-eu-text-lo hover:text-eu-accent-red-fg hover:bg-eu-accent-red-bg",
              "transition-colors duration-eu-fast",
            ].join(" ")}
          >
            <Trash2 size={14} strokeWidth={1.75} />
          </button>
        )}
      </div>

      {loading && <SkeletonList />}
      {empty && (
        <div className="rounded-eu-lg border border-dashed border-eu-border p-eu-xl text-center">
          <div className="text-eu-text-mid text-eu-sm">还没有 {titleText}</div>
          <div className="text-eu-text-lo text-eu-xs mt-1 font-mono">
            通过闪念 / Agent / 「+」按钮创建
          </div>
        </div>
      )}

      <div className="flex flex-col gap-eu-sm">
        {cards.map((c) => (
          <SkillCard
            key={c.id}
            data={c.data}
            onClick={() => setSelectedId(c.id)}
            selected={selectedId === c.id}
            onToggleCheck={c.data.checkDone !== undefined && c.id
              ? (next) => toggleTodo(c.id, next)
              : undefined}
          />
        ))}
      </div>

      {selectedCard && selectedPayload && (
        <AssetDetailDrawer
          card={selectedCard}
          payload={selectedPayload}
          sourceSessionId={selectedSource}
          onClose={() => setSelectedId(null)}
        />
      )}

      {deleteState !== "idle" && canDelete && (
        <DeleteSkillDialog
          skillName={titleText}
          assetCount={cards.length}
          state={deleteState}
          onCancel={() => setDeleteState("idle")}
          onConfirm={() => handleDelete(deleteState === "force-confirm")}
        />
      )}
    </div>
  );
}

/**
 * DeleteSkillDialog — two-stage confirm.
 *
 * Stage 1 ("confirm"):       skill has zero assets → simple "确定删除?"
 * Stage 2 ("force-confirm"): assets exist → caller passes the count, we
 *                            show "这会同时删除 N 条记录" and require an
 *                            extra tap. force=true is sent to backend.
 */
function DeleteSkillDialog({
  skillName, assetCount, state, onCancel, onConfirm,
}: {
  skillName: string;
  assetCount: number;
  state: "confirm" | "force-confirm" | "deleting";
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const isForce = state === "force-confirm";
  const isBusy = state === "deleting";
  return (
    <div
      className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-eu-bg/85 backdrop-blur-sm"
      onClick={isBusy ? undefined : onCancel}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full md:w-[420px] bg-eu-surface-raised border-t md:border md:rounded-eu-lg border-eu-border p-eu-lg flex flex-col gap-eu-md eu-sheet-up"
      >
        <div className="text-eu-lg font-medium text-eu-text-hi">
          {isForce ? `删除「${skillName}」?` : `删除「${skillName}」?`}
        </div>
        <div className="text-eu-sm text-eu-text-mid leading-relaxed">
          {isForce ? (
            <>这会同时删除该技能下的 <span className="text-eu-accent-red-fg font-medium">{assetCount}</span> 条记录,无法恢复。</>
          ) : (
            "技能将从你的资产库移除。"
          )}
        </div>
        <div className="flex justify-end gap-eu-sm pt-eu-sm">
          <button
            type="button"
            onClick={onCancel}
            disabled={isBusy}
            className="px-eu-md py-eu-sm rounded-eu-md text-eu-text-mid hover:bg-eu-surface-hover text-eu-sm disabled:opacity-50"
          >
            取消
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isBusy}
            className="px-eu-md py-eu-sm rounded-eu-md bg-eu-accent-red-bg border border-eu-accent-red-edge text-eu-accent-red-fg text-eu-sm font-medium hover:brightness-110 active:scale-95 disabled:opacity-50"
          >
            {isBusy ? "删除中…" : isForce ? "确定全部删除" : "确定删除"}
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Helpers ────────────────────────────────────────────────────────────── */

const FALLBACK_LABEL: Record<string, string> = {
  event:   "事件",
  file:    "文件",
  contact: "联系人",
};

function fileLabel(f: { source_tag: string | null; created_at: string }): string {
  // Files don't carry a user-visible name natively — synthesize one
  const tag = f.source_tag === "flash" ? "🎙 闪念录音"
            : f.source_tag === "meeting" ? "📁 会议录音"
            : "📎 文件";
  const d = new Date(f.created_at);
  const date = `${d.getMonth() + 1}/${d.getDate()}`;
  return `${tag} · ${date}`;
}

function SkeletonList() {
  return (
    <div className="flex flex-col gap-eu-sm">
      {[...Array(5)].map((_, i) => (
        <div
          key={i}
          className="h-16 rounded-eu-md bg-eu-surface animate-pulse opacity-50"
        />
      ))}
    </div>
  );
}
