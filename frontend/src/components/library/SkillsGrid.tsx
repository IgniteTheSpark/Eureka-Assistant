import { useEffect, useRef, useState, useCallback } from "react";
import { Plus, Sparkles, X } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useSWRConfig } from "swr";

import { AddSkillWizard } from "@/components/skill/AddSkillWizard";
import { apiFetch } from "@/lib/api";
import { reorderSkills } from "@/hooks/useSkillRegistry";

/**
 * SkillsGrid — the 3×3 SKILLS section in the library, with iOS-Springboard
 * style edit mode (long-press → wiggle + delete × on user-created tiles +
 * drag to reorder).
 *
 * Layout:
 *   ┌──────┬──────┬──────┐
 *   │  +   │ todo │ idea │   first slot is always the new-skill tile
 *   ├──────┼──────┼──────┤   (only when user has < SKILL_CAP user skills).
 *   │ note │ ...  │      │   At the cap, all 9 cells are skills.
 *   └──────┴──────┴──────┘
 *
 * Edit-mode interactions:
 *   - Long-press any tile (~480ms)            → enter edit mode (wiggle).
 *   - Tap × on a deletable tile               → confirms then deletes.
 *   - Pointer-down + drag a tile to another   → swaps positions; commits
 *     slot                                       via PUT /api/skills/reorder
 *                                               on pointer release.
 *   - Tap outside the grid                    → exit edit mode.
 *
 * Seeded canonical skills (todo / idea / notes / expense / misc) are
 * reorderable but NOT deletable — backend `PROTECTED_SKILLS` mirrors this.
 * The × button only renders on user-created tiles.
 */

export interface SkillTileData {
  /** UserSkill.id — stable key + drag identity. */
  user_skill_id: string;
  /** Skill machine name (used in the route /library/{name}). */
  name: string;
  label:  string;
  icon:   string;
  accent: TileAccent;
  /** Item count, rendered in the bottom-right of the tile. */
  count: number;
  preview?: string;
  /** False for seeded / first-class types — × button is suppressed. */
  deletable: boolean;
}

export type TileAccent = "blue" | "amber" | "green" | "neutral" | "purple";

const SKILL_CAP = 9;
const LONG_PRESS_MS = 480;
const DRAG_THRESHOLD_PX = 8;

interface SkillsGridProps {
  /** Already filtered + sorted (by `position` ASC). */
  tiles: SkillTileData[];
}

export function SkillsGrid({ tiles: initialTiles }: SkillsGridProps) {
  const navigate = useNavigate();
  const { mutate } = useSWRConfig();
  const [tiles, setTiles] = useState(initialTiles);
  const [editMode, setEditMode] = useState(false);
  const [dragIdx, setDragIdx] = useState<number | null>(null);
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
  const [wizardOpen, setWizardOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<SkillTileData | null>(null);

  const longPressTimer = useRef<number | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const tileRefs = useRef<Array<HTMLDivElement | null>>([]);
  const dragStartRef = useRef({ x: 0, y: 0 });
  const pointerIdRef = useRef<number | null>(null);
  const draggedFlagRef = useRef(false);

  // Keep local state in sync when props refresh (post-add, post-delete, SWR).
  useEffect(() => {
    setTiles(initialTiles);
  }, [initialTiles]);

  // Tap outside grid → exit edit mode.
  useEffect(() => {
    if (!editMode) return;
    const onDocDown = (e: PointerEvent) => {
      const t = e.target as HTMLElement;
      if (!containerRef.current?.contains(t)) {
        setEditMode(false);
        setDragIdx(null);
      }
    };
    document.addEventListener("pointerdown", onDocDown);
    return () => document.removeEventListener("pointerdown", onDocDown);
  }, [editMode]);

  const atCap = tiles.length >= SKILL_CAP;
  const showPlus = !editMode && !atCap;

  const persistOrder = useCallback(async (next: SkillTileData[]) => {
    try {
      await reorderSkills(next.map((t) => t.user_skill_id));
      await mutate("/api/skills");
    } catch {
      // On failure: revert visual to last server state by triggering refetch.
      await mutate("/api/skills");
    }
  }, [mutate]);

  function clearLongPress() {
    if (longPressTimer.current != null) {
      window.clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
  }

  function handlePointerDown(idx: number, e: React.PointerEvent) {
    // Only primary button on mouse; touch/pen always have button=0.
    if (e.button !== 0) return;

    dragStartRef.current = { x: e.clientX, y: e.clientY };
    draggedFlagRef.current = false;

    if (editMode) {
      // Start drag immediately.
      pointerIdRef.current = e.pointerId;
      setDragIdx(idx);
      setDragOffset({ x: 0, y: 0 });
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
      return;
    }

    // Not in edit mode: arm long-press timer; cancel on early move.
    clearLongPress();
    longPressTimer.current = window.setTimeout(() => {
      longPressTimer.current = null;
      setEditMode(true);
      try { navigator.vibrate?.(20); } catch { /* iOS Safari may throw */ }
    }, LONG_PRESS_MS);
  }

  function handlePointerMove(_idx: number, e: React.PointerEvent) {
    const dx = e.clientX - dragStartRef.current.x;
    const dy = e.clientY - dragStartRef.current.y;
    const moved = Math.abs(dx) > DRAG_THRESHOLD_PX || Math.abs(dy) > DRAG_THRESHOLD_PX;

    if (longPressTimer.current != null && moved) {
      clearLongPress();
      return;
    }

    if (dragIdx === null || e.pointerId !== pointerIdRef.current) return;

    setDragOffset({ x: dx, y: dy });
    if (Math.abs(dx) > 2 || Math.abs(dy) > 2) draggedFlagRef.current = true;

    // Hit-test the other tiles. If our pointer is now over another tile,
    // swap positions in the array and reset the drag origin so subsequent
    // movement is relative to the new slot.
    const x = e.clientX;
    const y = e.clientY;
    for (let i = 0; i < tiles.length; i++) {
      if (i === dragIdx) continue;
      const el = tileRefs.current[i];
      if (!el) continue;
      const r = el.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
        const next = [...tiles];
        const [moving] = next.splice(dragIdx, 1);
        next.splice(i, 0, moving);
        setTiles(next);
        setDragIdx(i);
        dragStartRef.current = { x: e.clientX, y: e.clientY };
        setDragOffset({ x: 0, y: 0 });
        break;
      }
    }
  }

  function handlePointerUp(_idx: number, e: React.PointerEvent) {
    clearLongPress();
    if (dragIdx !== null && e.pointerId === pointerIdRef.current) {
      const didDrag = draggedFlagRef.current;
      const next = tiles;
      setDragIdx(null);
      setDragOffset({ x: 0, y: 0 });
      pointerIdRef.current = null;
      if (didDrag) {
        void persistOrder(next);
      }
    }
  }

  function handleTileTap(idx: number, e: React.MouseEvent) {
    // Suppress navigation in edit mode and after a drag.
    if (editMode || draggedFlagRef.current) {
      e.preventDefault();
      return;
    }
    navigate(`/library/${tiles[idx].name}`);
  }

  async function executeDelete(force: boolean) {
    if (!confirmDelete) return;
    try {
      await apiFetch<{ ok: boolean; deleted_assets?: number; error?: string }>(
        `/api/skills/${confirmDelete.user_skill_id}${force ? "?force=true" : ""}`,
        { method: "DELETE" },
      );
      await mutate((key) =>
        typeof key === "string" && (key.startsWith("/api/skills") || key.startsWith("/api/assets")),
      );
      setConfirmDelete(null);
    } catch (err) {
      // Re-throw via console; modal stays open so user can retry.
      console.error("delete skill failed", err);
    }
  }

  return (
    <>
      <div
        ref={containerRef}
        className="grid grid-cols-3 gap-2.5"
        style={{ margin: "6px 0 22px" }}
      >
        {showPlus && (
          <PlusTile onClick={() => setWizardOpen(true)} />
        )}
        {tiles.map((tile, i) => {
          const isDragging = dragIdx === i;
          return (
            <div
              key={tile.user_skill_id}
              ref={(el) => { tileRefs.current[i] = el; }}
              onPointerDown={(e) => handlePointerDown(i, e)}
              onPointerMove={(e) => handlePointerMove(i, e)}
              onPointerUp={(e) => handlePointerUp(i, e)}
              onPointerCancel={(e) => handlePointerUp(i, e)}
              onClick={(e) => handleTileTap(i, e)}
              className={[
                "relative select-none",
                editMode && !isDragging ? "eu-wiggle" : "",
              ].join(" ")}
              style={{
                touchAction: editMode ? "none" : "manipulation",
                transform: isDragging
                  ? `translate(${dragOffset.x}px, ${dragOffset.y}px) scale(1.05)`
                  : undefined,
                zIndex: isDragging ? 30 : 1,
                transition: isDragging ? "none" : "transform 240ms cubic-bezier(.2,.7,.3,1)",
                cursor: editMode ? "grab" : "pointer",
              }}
            >
              <TileFace tile={tile} dimmed={editMode} />
              {editMode && tile.deletable && (
                <button
                  type="button"
                  onPointerDown={(e) => {
                    // Stop the parent drag/longpress handlers from claiming the event.
                    e.stopPropagation();
                  }}
                  onClick={(e) => {
                    e.stopPropagation();
                    setConfirmDelete(tile);
                  }}
                  aria-label={`删除 ${tile.label}`}
                  style={{
                    position: "absolute", top: -6, left: -6,
                    width: 20, height: 20, borderRadius: 999,
                    background: "#1a1d28",
                    border: "1.5px solid rgba(255,255,255,0.55)",
                    color: "#fff",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    cursor: "pointer",
                    boxShadow: "0 2px 6px rgba(0,0,0,0.45)",
                  }}
                >
                  <X size={11} strokeWidth={3} />
                </button>
              )}
            </div>
          );
        })}
      </div>

      {wizardOpen && <AddSkillWizard onClose={() => setWizardOpen(false)} />}
      {confirmDelete && (
        <DeleteSkillDialog
          tile={confirmDelete}
          onCancel={() => setConfirmDelete(null)}
          onConfirm={(force) => executeDelete(force)}
        />
      )}
    </>
  );
}

/* ── Tile sub-views ──────────────────────────────────────────────────────── */

const ACCENT_BG: Record<TileAccent, string> = {
  blue:    "rgba(111,158,255,0.12)",
  amber:   "rgba(245,201,119,0.12)",
  green:   "rgba(134,224,165,0.12)",
  purple:  "rgba(196,168,255,0.12)",
  neutral: "rgba(255,255,255,0.04)",
};
const ACCENT_BORDER: Record<TileAccent, string> = {
  blue:    "rgba(111,158,255,0.32)",
  amber:   "rgba(245,201,119,0.32)",
  green:   "rgba(134,224,165,0.32)",
  purple:  "rgba(196,168,255,0.32)",
  neutral: "rgba(255,255,255,0.08)",
};
const ACCENT_FG: Record<TileAccent, string> = {
  blue:    "#6f9eff",
  amber:   "#f5c977",
  green:   "#86e0a5",
  purple:  "#c4a8ff",
  neutral: "rgba(255,255,255,0.55)",
};

function TileFace({ tile, dimmed }: { tile: SkillTileData; dimmed: boolean }) {
  return (
    <div
      className="flex flex-col text-left"
      style={{
        padding: "10px 10px", borderRadius: 12,
        background: ACCENT_BG[tile.accent],
        border: `1px solid ${ACCENT_BORDER[tile.accent]}`,
        minHeight: 78,
        color: "inherit",
        gap: 6,
        opacity: dimmed ? 0.92 : 1,
        transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
      }}
    >
      <span
        style={{
          width: 28, height: 28, borderRadius: 8,
          background: ACCENT_BG[tile.accent],
          border: `1px solid ${ACCENT_BORDER[tile.accent]}`,
          display: "flex", alignItems: "center", justifyContent: "center",
          color: ACCENT_FG[tile.accent], fontSize: 14,
        }}
      >
        {tile.icon}
      </span>
      <div className="flex items-baseline justify-between" style={{ marginTop: "auto" }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: "#f4f7fb" }}>{tile.label}</span>
        <span
          className="font-mono"
          style={{ fontSize: 11, color: ACCENT_FG[tile.accent], fontWeight: 600 }}
        >
          {tile.count}
        </span>
      </div>
    </div>
  );
}

function PlusTile({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex flex-col text-left active:scale-95"
      style={{
        gap: 6,
        padding: "10px 10px", borderRadius: 12,
        background: "rgba(196,168,255,0.04)",
        border: "1px dashed rgba(196,168,255,0.32)",
        minHeight: 78,
        color: "inherit", cursor: "pointer",
        transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
      }}
    >
      <span
        style={{
          width: 28, height: 28, borderRadius: 8,
          background: "rgba(196,168,255,0.10)",
          border: "1px solid rgba(196,168,255,0.32)",
          display: "flex", alignItems: "center", justifyContent: "center",
          color: "#c4a8ff",
          boxShadow: "inset 0 0 12px rgba(196,168,255,0.30)",
        }}
      >
        <Sparkles size={13} strokeWidth={1.75} />
      </span>
      <div className="flex items-baseline justify-between" style={{ marginTop: "auto" }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: "#f4f7fb" }}>新技能</span>
        <span
          className="font-mono"
          style={{ fontSize: 10, color: "rgba(196,168,255,0.65)", letterSpacing: "0.14em" }}
        >
          <Plus size={12} strokeWidth={2.5} />
        </span>
      </div>
    </button>
  );
}

/* ── Delete confirm sheet ────────────────────────────────────────────────── */

function DeleteSkillDialog({
  tile, onCancel, onConfirm,
}: {
  tile: SkillTileData;
  onCancel: () => void;
  onConfirm: (force: boolean) => void;
}) {
  const hasAssets = tile.count > 0;
  return (
    <div
      className="fixed inset-0 z-[60] flex items-end md:items-center justify-center bg-eu-bg/85 backdrop-blur-sm"
      onClick={onCancel}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full md:w-[420px] bg-eu-surface-raised border-t md:border md:rounded-eu-lg border-eu-border p-eu-lg flex flex-col gap-eu-md eu-sheet-up"
      >
        <div className="text-eu-lg font-medium text-eu-text-hi">删除「{tile.label}」?</div>
        <div className="text-eu-sm text-eu-text-mid leading-relaxed">
          {hasAssets
            ? <>这会同时删除该技能下的 <span className="text-eu-accent-red-fg font-medium">{tile.count}</span> 条记录,无法恢复。</>
            : "技能将从你的资产库移除。"}
        </div>
        <div className="flex justify-end gap-eu-sm pt-eu-sm">
          <button
            type="button"
            onClick={onCancel}
            className="px-eu-md py-eu-sm rounded-eu-md text-eu-text-mid hover:bg-eu-surface-hover text-eu-sm"
          >
            取消
          </button>
          <button
            type="button"
            onClick={() => onConfirm(hasAssets)}
            className="px-eu-md py-eu-sm rounded-eu-md bg-eu-accent-red-bg border border-eu-accent-red-edge text-eu-accent-red-fg text-eu-sm font-medium hover:brightness-110 active:scale-95"
          >
            {hasAssets ? "确定全部删除" : "确定删除"}
          </button>
        </div>
      </div>
    </div>
  );
}
