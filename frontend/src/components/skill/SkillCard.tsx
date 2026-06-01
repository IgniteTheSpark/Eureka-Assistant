import { Check } from "lucide-react";

import { McpBrandMark, isMcpBrand } from "@/components/skill/McpBrandMark";
import type { AccentColor, CardData, CardLayout } from "@/lib/render-spec";

/**
 * SkillCard — the universal render_spec-driven card.
 *
 * One component, 4 layouts (horizontal / stacked / inline / compact),
 * driven entirely by the CardData object produced by `buildCard` in
 * lib/render-spec.ts. Per Phase D spec §九, adding a new skill needs no
 * change here — its render_spec drives the look.
 *
 * Atmosphere visual language (per docs/rebuild/design-canvas/var-b-atmosphere.jsx):
 *   - Tinted card background (`bg-eu-accent-<c>-bg`)
 *   - Soft accent edge (`border-eu-accent-<c>-edge`)
 *   - Icon tile: gradient bg, inset glow, mono font
 *   - Hover: soft glow shadow lifts the card
 *   - Transition: 240ms cubic-bezier(.2,.7,.3,1)
 */

interface SkillCardProps {
  data: CardData;
  onClick?: () => void;
  selected?: boolean;
  /** Override layout (e.g. when used inline in chat) */
  layoutOverride?: CardLayout;
  /** OP3: called when the user taps the checkbox (only rendered when
   *  data.checkDone is defined, ie. spec has "check" action). Receives
   *  the NEW desired done-state. Caller is responsible for PUT-ing the
   *  asset and mutating SWR caches. */
  onToggleCheck?: (nextDone: boolean) => void;
}

export function SkillCard({ data, onClick, selected, layoutOverride, onToggleCheck }: SkillCardProps) {
  const layout = layoutOverride ?? data.layout;
  switch (layout) {
    case "inline":   return <InlineCard data={data} onClick={onClick} />;
    case "compact":  return <CompactCard data={data} onClick={onClick} />;
    case "stacked":  return <StackedCard data={data} onClick={onClick} selected={selected} onToggleCheck={onToggleCheck} />;
    case "horizontal":
    default:         return <HorizontalCard data={data} onClick={onClick} selected={selected} onToggleCheck={onToggleCheck} />;
  }
}

/* ── Layouts ─────────────────────────────────────────────────────────────── */

function HorizontalCard({
  data, onClick, selected, onToggleCheck,
}: {
  data: CardData; onClick?: () => void; selected?: boolean;
  onToggleCheck?: (next: boolean) => void;
}) {
  const a = ACCENT[data.accentColor];
  const hasCheck = data.checkDone !== undefined;
  const done = data.checkDone === true;

  return (
    <CardShell accent={data.accentColor} selected={selected} onClick={onClick}>
      <IconTile
        icon={data.icon}
        accent={data.accentColor}
        check={hasCheck ? { done, onClick: (e) => { e.stopPropagation(); onToggleCheck?.(!done); } } : undefined}
      />
      <div className="flex-1 min-w-0">
        <div
          className={[
            "text-eu-base font-medium leading-snug tracking-tight truncate",
            done ? "text-eu-text-lo line-through" : "text-eu-text-hi",
          ].join(" ")}
        >
          {data.title}
        </div>
        {(data.subtitle || data.metaFields.length > 0) && (
          <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
            {data.subtitle && (
              <span
                className={[
                  "text-eu-sm truncate",
                  done ? "text-eu-text-lo line-through" : "text-eu-text-mid",
                ].join(" ")}
              >
                {data.subtitle}
              </span>
            )}
            {data.metaFields.map((m, i) => (
              <MetaPill key={`${m.field}-${i}`} value={m.value} format={m.format} accentClass={a.metaFg} />
            ))}
          </div>
        )}
      </div>
    </CardShell>
  );
}

function StackedCard({
  data, onClick, selected, onToggleCheck,
}: {
  data: CardData; onClick?: () => void; selected?: boolean;
  onToggleCheck?: (next: boolean) => void;
}) {
  const hasCheck = data.checkDone !== undefined;
  const done = data.checkDone === true;
  return (
    <CardShell accent={data.accentColor} selected={selected} onClick={onClick} extraClass="flex-col items-stretch gap-eu-sm py-eu-md">
      <div className="flex items-center gap-eu-sm">
        {hasCheck
          ? <CheckTile done={done} accent={data.accentColor}
              onClick={(e) => { e.stopPropagation(); onToggleCheck?.(!done); }} />
          : <IconTile icon={data.icon} accent={data.accentColor} />}
        <div className={[
          "text-eu-base font-medium tracking-tight flex-1 min-w-0 truncate",
          done ? "text-eu-text-lo line-through" : "text-eu-text-hi",
        ].join(" ")}>
          {data.title}
        </div>
      </div>
      {data.subtitle && (
        <p className="text-eu-sm text-eu-text leading-relaxed line-clamp-3">{data.subtitle}</p>
      )}
      {data.metaFields.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 pt-1">
          {data.metaFields.map((m, i) => (
            <MetaPill key={`${m.field}-${i}`} value={m.value} format={m.format} accentClass={ACCENT[data.accentColor].metaFg} />
          ))}
        </div>
      )}
    </CardShell>
  );
}

function InlineCard({ data, onClick }: { data: CardData; onClick?: () => void }) {
  const a = ACCENT[data.accentColor];
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "flex items-center gap-eu-sm",
        "px-eu-md py-2 rounded-eu-md",
        a.bg, a.border, "border",
        "text-eu-sm text-eu-text",
        "transition-all duration-eu-fast ease-eu-out",
        "hover:brightness-110 active:scale-[0.99]",
        "w-full text-left",
      ].join(" ")}
    >
      <span className={`font-mono text-eu-sm ${a.iconFg}`}>{data.icon}</span>
      <span className="flex-1 truncate">{data.title}</span>
      {data.subtitle && (
        <span className="text-eu-xs text-eu-text-lo font-mono shrink-0">{data.subtitle}</span>
      )}
    </button>
  );
}

function CompactCard({ data, onClick }: { data: CardData; onClick?: () => void }) {
  const a = ACCENT[data.accentColor];
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "inline-flex items-center gap-1.5",
        "px-2 py-1 rounded-md",
        a.bg, a.border, "border",
        a.iconFg,
        "text-eu-xs font-medium",
        "transition-all duration-eu-fast ease-eu-out",
        "hover:brightness-110",
      ].join(" ")}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${a.dot}`} aria-hidden="true" />
      <span className="truncate max-w-[16ch]">{data.title}</span>
    </button>
  );
}

/* ── Shared pieces ───────────────────────────────────────────────────────── */

function CardShell({
  accent, selected, onClick, extraClass = "", children,
}: {
  accent: AccentColor;
  selected?: boolean;
  onClick?: () => void;
  extraClass?: string;
  children: React.ReactNode;
}) {
  const a = ACCENT[accent];
  const interactive = onClick != null;
  const Tag = interactive ? "button" : "div";
  // Stop propagation so that opening a modal (e.g. AssetDetailDrawer) on click
  // doesn't immediately close it via the modal's backdrop click handler — the
  // same native click would otherwise bubble through and hit the backdrop
  // React just rendered into the DOM.
  const handleClick = onClick
    ? (e: React.MouseEvent) => { e.stopPropagation(); onClick(); }
    : undefined;
  return (
    <Tag
      type={interactive ? "button" : undefined}
      onClick={handleClick}
      className={[
        "group flex items-center gap-eu-md",
        "px-eu-md py-eu-md rounded-eu-md",
        a.bg, "border", selected ? a.borderStrong : a.border,
        "text-left w-full",
        "transition-all duration-[240ms] ease-[cubic-bezier(.2,.7,.3,1)]",
        interactive && "hover:brightness-110 hover:shadow-eu-md active:scale-[0.995] cursor-pointer",
        selected && a.glowShadow,
        extraClass,
      ].filter(Boolean).join(" ")}
    >
      {children}
    </Tag>
  );
}

/**
 * IconTile — every card's left-side identity block. Always renders the
 * skill's icon so a todo still looks like a todo (its 🟢/⏳/⭐ etc.). When
 * `check` is provided (skill has the "check" action), a small checkbox
 * overlay floats in the bottom-right corner of the tile — both the icon and
 * the check state are visible simultaneously (#2, May audit). Done state
 * dims the icon so the visual weight follows completion.
 */
function IconTile({
  icon, accent, check,
}: {
  icon: string;
  accent: AccentColor;
  check?: { done: boolean; onClick: (e: React.MouseEvent) => void };
}) {
  const a = ACCENT[accent];
  // MCP brand cards (e.g. 钉钉) render the real logo tile instead of a glyph.
  // These never have a check action, so no overlay to worry about.
  if (isMcpBrand(icon)) {
    return <McpBrandMark icon={icon} size={32} radius={9} />;
  }
  return (
    <div className="relative shrink-0 h-8 w-8">
      <div
        className={[
          "h-8 w-8 rounded-eu-md",
          "flex items-center justify-center",
          "font-mono font-semibold text-eu-md",
          a.iconBg, a.iconFg, "border", a.border,
          "shadow-[inset_0_0_12px_rgba(255,255,255,0.04)]",
          check?.done ? "opacity-50" : "",
        ].join(" ")}
      >
        {icon}
      </div>
      {check && (
        <button
          type="button"
          onClick={check.onClick}
          aria-label={check.done ? "标记未完成" : "标记完成"}
          className={[
            // Sits on the bottom-right corner, slightly overhanging.
            "absolute -bottom-1 -right-1 h-[15px] w-[15px] rounded-full",
            "flex items-center justify-center",
            "border transition-all duration-eu-fast ease-eu-out",
            "active:scale-85",
            check.done
              ? `${a.iconBg} ${a.border} text-white`
              : `bg-eu-bg ${a.border} ${a.iconFg} hover:${a.iconBg}`,
            // A faint ring against any background — the tile sits over
            // varying surfaces (raised, glass) and the overlay needs lift.
            "ring-1 ring-eu-bg/80",
          ].join(" ")}
        >
          {check.done && <Check size={9} strokeWidth={3.5} />}
        </button>
      )}
    </div>
  );
}

/**
 * Async-task lifecycle statuses (external_ref / task cards). When a badge
 * meta-field carries one of these raw values, render it localized + colored
 * by state instead of the card's flat accent — this is the task-status UI for
 * third-party MCP calls (pending → running → done/failed). pending/running
 * pulse to read as "in flight".
 */
const LIFECYCLE_STATUS: Record<string, { label: string; cls: string; pulse?: boolean }> = {
  pending: { label: "待处理", cls: "text-eu-accent-amber-fg bg-eu-accent-amber-bg", pulse: true },
  running: { label: "同步中", cls: "text-eu-accent-blue-fg bg-eu-accent-blue-bg",  pulse: true },
  done:    { label: "已同步", cls: "text-eu-accent-green-fg bg-eu-accent-green-bg" },
  failed:  { label: "失败",   cls: "text-eu-accent-red-fg bg-eu-accent-red-bg" },
};

function MetaPill({ value, format, accentClass }: { value: string; format?: string; accentClass: string }) {
  const isBadge = format === "badge";
  if (isBadge) {
    const st = LIFECYCLE_STATUS[value];
    if (st) {
      return (
        <span className={`px-1.5 py-0.5 rounded text-eu-xs font-medium ${st.cls} ${st.pulse ? "animate-pulse" : ""}`}>
          {st.label}
        </span>
      );
    }
    return (
      <span className={`px-1.5 py-0.5 rounded text-eu-xs font-medium ${accentClass} bg-white/5`}>
        {value}
      </span>
    );
  }
  return (
    <span className="text-eu-xs text-eu-text-lo font-mono">· {value}</span>
  );
}

/* ── Accent class map (Tailwind classes per accent_color) ─────────────────
 *
 * We can't dynamically build class names (Tailwind's purge would strip them);
 * map them explicitly so the purger keeps them. Tokens come from tokens.css.
 */

const ACCENT: Record<AccentColor, {
  bg: string;
  border: string;
  borderStrong: string;
  iconBg: string;
  iconFg: string;
  metaFg: string;
  dot: string;
  glowShadow: string;
}> = {
  blue: {
    bg: "bg-eu-accent-blue-bg",
    border: "border-eu-accent-blue-edge",
    borderStrong: "border-eu-accent-blue-solid",
    iconBg: "bg-eu-accent-blue-bg",
    iconFg: "text-eu-accent-blue-fg",
    metaFg: "text-eu-accent-blue-fg",
    dot: "bg-eu-accent-blue-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(111,158,255,0.18)]",
  },
  amber: {
    bg: "bg-eu-accent-amber-bg",
    border: "border-eu-accent-amber-edge",
    borderStrong: "border-eu-accent-amber-solid",
    iconBg: "bg-eu-accent-amber-bg",
    iconFg: "text-eu-accent-amber-fg",
    metaFg: "text-eu-accent-amber-fg",
    dot: "bg-eu-accent-amber-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(245,201,119,0.18)]",
  },
  green: {
    bg: "bg-eu-accent-green-bg",
    border: "border-eu-accent-green-edge",
    borderStrong: "border-eu-accent-green-solid",
    iconBg: "bg-eu-accent-green-bg",
    iconFg: "text-eu-accent-green-fg",
    metaFg: "text-eu-accent-green-fg",
    dot: "bg-eu-accent-green-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(134,224,165,0.18)]",
  },
  red: {
    bg: "bg-eu-accent-red-bg",
    border: "border-eu-accent-red-edge",
    borderStrong: "border-eu-accent-red-solid",
    iconBg: "bg-eu-accent-red-bg",
    iconFg: "text-eu-accent-red-fg",
    metaFg: "text-eu-accent-red-fg",
    dot: "bg-eu-accent-red-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(255,141,161,0.18)]",
  },
  purple: {
    bg: "bg-eu-accent-purple-bg",
    border: "border-eu-accent-purple-edge",
    borderStrong: "border-eu-accent-purple-solid",
    iconBg: "bg-eu-accent-purple-bg",
    iconFg: "text-eu-accent-purple-fg",
    metaFg: "text-eu-accent-purple-fg",
    dot: "bg-eu-accent-purple-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(196,168,255,0.18)]",
  },
  gray: {
    bg: "bg-eu-accent-gray-bg",
    border: "border-eu-accent-gray-edge",
    borderStrong: "border-eu-accent-gray-solid",
    iconBg: "bg-eu-accent-gray-bg",
    iconFg: "text-eu-accent-gray-fg",
    metaFg: "text-eu-accent-gray-fg",
    dot: "bg-eu-accent-gray-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(154,166,184,0.16)]",
  },
  neutral: {
    bg: "bg-eu-accent-neutral-bg",
    border: "border-eu-accent-neutral-edge",
    borderStrong: "border-eu-accent-neutral-solid",
    iconBg: "bg-eu-accent-neutral-bg",
    iconFg: "text-eu-accent-neutral-fg",
    metaFg: "text-eu-accent-neutral-fg",
    dot: "bg-eu-accent-neutral-solid",
    glowShadow: "shadow-[0_6px_24px_rgba(212,219,230,0.14)]",
  },
};
