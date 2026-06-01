import { useState } from "react";
import useSWR from "swr";
import { Check, X } from "lucide-react";

import { useModalMount } from "@/context/ModalContext";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { swrFetcher } from "@/lib/api";
import type { AssetsResponse } from "@/lib/types";
import type { AccentColor } from "@/lib/render-spec";

/**
 * AssetPickerSheet — modal for selecting one or more assets to add as
 * context to the current chat session (M2.3 + 添加资产 button).
 *
 * MVP: flat list of all assets newest-first, multi-select checkboxes, top
 * "已选 N" + 「添加」 confirm button. No filter/search/per-skill drill —
 * that comes when the list grows too long.
 */

interface AssetPickerSheetProps {
  onConfirm: (assetIds: string[]) => void;
  onClose: () => void;
  /** Asset IDs already in context — show as disabled / already-added */
  excludeIds?: string[];
}

export function AssetPickerSheet({ onConfirm, onClose, excludeIds = [] }: AssetPickerSheetProps) {
  useModalMount();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const { bySkill } = useSkillRegistry();
  const { data, isLoading } = useSWR<AssetsResponse>("/api/assets?limit=200", swrFetcher);

  const excludeSet = new Set(excludeIds);
  const assets = (data?.assets ?? []).filter((a) => !excludeSet.has(a.id));

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function confirm() {
    if (selected.size === 0) return;
    onConfirm(Array.from(selected));
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md flex items-end md:items-center justify-center eu-fade-in"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className={[
          "w-full",
          "bg-eu-surface-raised border-t border-eu-border md:border md:rounded-eu-xl",
          "rounded-t-eu-xl shadow-eu-lg pt-eu-md pb-safe",
          "eu-sheet-up",
          "flex flex-col max-h-[85vh]",
        ].join(" ")}
      >
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />
        <header className="flex items-center justify-between px-eu-lg pb-eu-sm">
          <h2 className="font-display text-eu-lg text-eu-text-hi tracking-tight">添加到上下文</h2>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </header>

        <div className="px-eu-lg pb-eu-sm text-eu-xs text-eu-text-lo font-mono">
          选中的资产会作为 context 注入到 chat,Agent 可以基于它们回答
        </div>

        <div className="flex-1 overflow-y-auto eu-noscroll px-eu-md">
          {isLoading && <div className="text-eu-sm text-eu-text-lo px-eu-sm py-eu-md">加载中…</div>}
          {!isLoading && assets.length === 0 && (
            <div className="text-eu-sm text-eu-text-lo px-eu-sm py-eu-md">
              {excludeIds.length > 0 ? "没有更多可加的资产" : "还没有资产"}
            </div>
          )}
          <div className="flex flex-col gap-1">
            {assets.map((a) => {
              const skill = bySkill.get(a.user_skill_name);
              const icon = skill?.render_spec?.icon ?? "•";
              const accent = (skill?.render_spec?.accent_color ?? "gray") as AccentColor;
              const p = a.payload as { content?: unknown; title?: unknown; name?: unknown };
              const title = String(p.content ?? p.title ?? p.name ?? a.user_skill_name);
              const isSelected = selected.has(a.id);
              return (
                <button
                  key={a.id}
                  type="button"
                  onClick={() => toggle(a.id)}
                  className={[
                    "w-full flex items-center gap-eu-sm px-eu-sm py-eu-sm rounded-eu-md text-left",
                    "transition-all duration-eu-fast",
                    isSelected
                      ? "bg-eu-brand-faint border border-eu-brand-line"
                      : "hover:bg-eu-surface-hover border border-transparent",
                  ].join(" ")}
                >
                  <div className={[
                    "shrink-0 h-8 w-8 rounded-eu-md border",
                    "flex items-center justify-center font-mono",
                    ACCENT_BG[accent], ACCENT_FG[accent], ACCENT_BORDER[accent],
                  ].join(" ")}>{icon}</div>
                  <div className="flex-1 min-w-0">
                    <div className="text-eu-sm text-eu-text-hi truncate">{title}</div>
                    <div className="text-eu-xs text-eu-text-lo font-mono mt-0.5">
                      {skill?.display_name ?? a.user_skill_name}
                    </div>
                  </div>
                  {isSelected && (
                    <Check size={16} strokeWidth={2} className="shrink-0 text-eu-brand-hi" />
                  )}
                </button>
              );
            })}
          </div>
        </div>

        <footer className="border-t border-eu-rule px-eu-lg pt-eu-md flex items-center justify-between">
          <div className="text-eu-sm text-eu-text-mid">已选 {selected.size}</div>
          <div className="flex gap-eu-sm">
            <button
              type="button"
              onClick={onClose}
              className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi"
            >
              取消
            </button>
            <button
              type="button"
              onClick={confirm}
              disabled={selected.size === 0}
              className={[
                "px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                "bg-eu-brand text-white hover:bg-eu-brand-hi",
                "disabled:opacity-50 disabled:cursor-not-allowed",
                "transition-colors duration-eu-fast",
              ].join(" ")}
            >
              添加 {selected.size > 0 ? `(${selected.size})` : ""}
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
}

const ACCENT_BG: Record<AccentColor, string> = {
  blue: "bg-eu-accent-blue-bg",       amber: "bg-eu-accent-amber-bg",
  green: "bg-eu-accent-green-bg",     red:   "bg-eu-accent-red-bg",
  purple: "bg-eu-accent-purple-bg",   gray:  "bg-eu-accent-gray-bg",
  neutral: "bg-eu-accent-neutral-bg",
};
const ACCENT_FG: Record<AccentColor, string> = {
  blue: "text-eu-accent-blue-fg",     amber: "text-eu-accent-amber-fg",
  green: "text-eu-accent-green-fg",   red:   "text-eu-accent-red-fg",
  purple: "text-eu-accent-purple-fg", gray:  "text-eu-accent-gray-fg",
  neutral: "text-eu-accent-neutral-fg",
};
const ACCENT_BORDER: Record<AccentColor, string> = {
  blue: "border-eu-accent-blue-edge",     amber: "border-eu-accent-amber-edge",
  green: "border-eu-accent-green-edge",   red:   "border-eu-accent-red-edge",
  purple: "border-eu-accent-purple-edge", gray:  "border-eu-accent-gray-edge",
  neutral: "border-eu-accent-neutral-edge",
};
