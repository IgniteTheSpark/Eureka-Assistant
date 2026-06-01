import { useState } from "react";
import { X } from "lucide-react";

import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useModalMount } from "@/context/ModalContext";
import { SkillCreateForm } from "@/components/skill/SkillCreateForm";
import { EventForm } from "@/components/calendar/EventForm";
import type { AccentColor } from "@/lib/render-spec";
import type { Skill } from "@/lib/types";

/**
 * CreateAssetMenu — bottom-sheet menu shown when user taps the + button on
 * the FloatingDock or LibraryPage.
 *
 * Asset-creation only: one tile per creatable type (event + every skill
 * with a render_spec). Tapping a tile opens that type's create form inline
 * (EventForm for 事件, SkillCreateForm for skills). The AI entry points
 * (跟 Agent 对话 / 闪念输入) deliberately live on the dock itself — the
 * Agent pill and 🎙 mic — not here, so the + is unambiguously "make a thing".
 */

interface CreateAssetMenuProps {
  open: boolean;
  onClose: () => void;
  /** OP10: optional default date — when opened from DayDetail, new
   *  events default to that day instead of "now". */
  defaultDate?: Date;
}

export function CreateAssetMenu({ open, onClose, defaultDate }: CreateAssetMenuProps) {
  if (!open) return null;
  return <CreateAssetMenuBody onClose={onClose} defaultDate={defaultDate} />;
}

function CreateAssetMenuBody({ onClose, defaultDate }: { onClose: () => void; defaultDate?: Date }) {
  useModalMount();
  const { skills } = useSkillRegistry();
  // When user picks a skill, swap the menu for that skill's create form.
  // (We don't unmount this component — the form sits as a sibling overlay.)
  const [activeSkill, setActiveSkill] = useState<Skill | null>(null);
  // Event is a first-class entity not a skill — separate state branch so
  // the EventForm can be triggered from the same tile grid.
  const [eventOpen,   setEventOpen]   = useState(false);

  if (eventOpen) {
    return (
      <EventForm defaultStart={defaultDate} onClose={() => { setEventOpen(false); onClose(); }} />
    );
  }

  if (activeSkill) {
    return (
      <SkillCreateForm
        skill={activeSkill}
        onClose={() => { setActiveSkill(null); onClose(); }}
      />
    );
  }

  const creatable = skills.filter(
    (s) => s.render_spec && s.name !== "qa" && s.name !== "external_ref",
  );

  return (
    <div
      // Heavy backdrop so the FloatingDock (Agent pill, calendar badge etc.)
      // doesn't bleed through and clash with the menu content above.
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
          "flex flex-col gap-eu-sm",
        ].join(" ")}
      >
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />
        <div className="flex items-center justify-between px-eu-lg">
          <h2 className="font-display text-eu-lg text-eu-text-hi tracking-tight">创建</h2>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="p-1 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </div>

        {/* The + is asset-creation only. The AI entries (跟 Agent 对话 /
            闪念输入) used to live here but were redundant with the dock's own
            Agent pill + 🎙 mic — so this sheet is now purely "create an asset
            of type X". */}
        <div className="px-eu-md pt-eu-sm pb-eu-md grid grid-cols-2 gap-eu-sm">
          {/* M4-bugfix-3: 事件 is first-class (not a skill) but the user
              expects to create one from this same grid. Hardcoded tile
              opens EventForm directly. */}
          <SkillTile
            icon="📅"
            label="事件"
            accent="purple"
            onClick={() => setEventOpen(true)}
          />
          {creatable.map((s) => (
            <SkillTile
              key={s.name}
              icon={s.render_spec!.icon ?? "•"}
              label={s.display_name}
              accent={(s.render_spec!.accent_color ?? "gray") as AccentColor}
              onClick={() => setActiveSkill(s)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function SkillTile({
  icon, label, accent, onClick,
}: { icon: string; label: string; accent: AccentColor; onClick: () => void }) {
  const map: Record<AccentColor, { bg: string; fg: string; border: string }> = {
    blue:    { bg: "bg-eu-accent-blue-bg",    fg: "text-eu-accent-blue-fg",    border: "border-eu-accent-blue-edge"    },
    amber:   { bg: "bg-eu-accent-amber-bg",   fg: "text-eu-accent-amber-fg",   border: "border-eu-accent-amber-edge"   },
    green:   { bg: "bg-eu-accent-green-bg",   fg: "text-eu-accent-green-fg",   border: "border-eu-accent-green-edge"   },
    red:     { bg: "bg-eu-accent-red-bg",     fg: "text-eu-accent-red-fg",     border: "border-eu-accent-red-edge"     },
    purple:  { bg: "bg-eu-accent-purple-bg",  fg: "text-eu-accent-purple-fg",  border: "border-eu-accent-purple-edge"  },
    gray:    { bg: "bg-eu-accent-gray-bg",    fg: "text-eu-accent-gray-fg",    border: "border-eu-accent-gray-edge"    },
    neutral: { bg: "bg-eu-accent-neutral-bg", fg: "text-eu-accent-neutral-fg", border: "border-eu-accent-neutral-edge" },
  };
  const a = map[accent];
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "flex items-center gap-eu-sm px-eu-md py-eu-sm rounded-eu-md",
        a.bg, "border", a.border,
        "hover:brightness-110 transition-all",
      ].join(" ")}
    >
      <span className={`font-mono text-eu-md ${a.fg}`}>{icon}</span>
      <span className="text-eu-sm text-eu-text-hi">{label}</span>
    </button>
  );
}
