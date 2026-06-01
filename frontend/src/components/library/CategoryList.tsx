import { Link, useNavigate } from "react-router-dom";
import useSWR from "swr";

import { EventCard } from "@/components/calendar/EventCard";
import { SkillCard } from "@/components/skill/SkillCard";
import { SkillsGrid, type SkillTileData, type TileAccent } from "@/components/library/SkillsGrid";
import { swrFetcher } from "@/lib/api";
import { buildCard } from "@/lib/render-spec";
import type { AccentColor } from "@/lib/render-spec";
import type {
  Asset, AssetsResponse, ContactsResponse, Event,
  EventsResponse, FileRow, FilesResponse,
} from "@/lib/types";
import { useSkillRegistry } from "@/hooks/useSkillRegistry";
import { useToggleTodo } from "@/hooks/useToggleTodo";

/**
 * LibraryHub — primary library view (M4-polish, replaces M1's 8-行 list).
 *
 * Implements `rebuild/design-canvas/var-b-calendar.jsx#CalAssetLibrary` and
 * design-system.md §6.1 literally:
 *
 *   ┌──────────────────────────────────────┐
 *   │ 资产库                            ⌕   │  ← big title + total count caps
 *   │ 27 ITEMS · LAST 30D                  │
 *   ├──────────────────────────────────────┤
 *   │ ┌──────────┐  ┌──────────┐           │  ← 2×3 (mobile) or 3×2 (desktop)
 *   │ │ ☑    14  │  │ ●     8  │           │    type tile grid
 *   │ │ 待办     │  │ 事件     │           │    each: icon-block (glow) +
 *   │ │ 财务对账 │  │ 产品评审 │           │    big mono count + label +
 *   │ └──────────┘  └──────────┘           │    "最近一个" preview
 *   │ ┌──────────┐  ┌──────────┐           │
 *   │ │ ◇    22  │  │ ¥     6  │           │
 *   │ │ 想法     │  │ 记账     │           │
 *   │ └──────────┘  └──────────┘           │
 *   │ ┌──────────┐  ┌──────────┐           │
 *   │ │ ◯    11  │  │ ♪     7  │           │
 *   │ │ 名片     │  │ 文件     │           │
 *   │ └──────────┘  └──────────┘           │
 *   │                                       │
 *   │ ──── 最近 ────────────                │  ← caps mono section label
 *   │ ┌──────────────────────────────────┐  │
 *   │ │ ◇ IDEA  SkillCard 的「沉淀」动画 │  │  ← cross-type latest 4-6
 *   │ │     ♪  14:32 · 闪念              │  │
 *   │ └──────────────────────────────────┘  │
 *   │ ┌──────────────────────────────────┐  │
 *   │ │ ● EVENT 产品评审 · Eureka v2     │  │
 *   │ │     5月27日 10:00                 │  │
 *   │ └──────────────────────────────────┘  │
 *   │                                       │
 *   │ ── 扩展 ──                            │
 *   │ ┌──────────────────────────────────┐  │
 *   │ │ ✨ 添加新技能                     │  │
 *   │ └──────────────────────────────────┘  │
 *   └──────────────────────────────────────┘
 *
 * Per-tile count + preview rules:
 *   - todo / idea / expense / notes / misc → /api/assets filtered by user_skill_name
 *   - contact → /api/contacts (real contacts table)
 *   - event   → /api/events
 *   - file    → /api/files
 *
 * Preview text = latest item's title-ish field (per skill).
 */

interface TileKind {
  key:       string;
  to:        string;
  label:     string;
  icon:      string;
  accent:    LibAccent;
}

type LibAccent = "blue" | "amber" | "green" | "purple" | "neutral" | "cyan";

const LIB_ACCENT: Record<LibAccent, { fg: string; bg: string; edge: string; glow: string }> = {
  blue:    { fg: "#8ab4ff", bg: "rgba(138,180,255,0.10)", edge: "rgba(138,180,255,0.24)", glow: "rgba(111,158,255,0.30)" },
  amber:   { fg: "#f5c977", bg: "rgba(245,201,119,0.10)", edge: "rgba(245,201,119,0.24)", glow: "rgba(245,201,119,0.30)" },
  green:   { fg: "#86e0a5", bg: "rgba(134,224,165,0.10)", edge: "rgba(134,224,165,0.24)", glow: "rgba(134,224,165,0.30)" },
  purple:  { fg: "#c4a8ff", bg: "rgba(196,168,255,0.10)", edge: "rgba(196,168,255,0.24)", glow: "rgba(196,168,255,0.30)" },
  neutral: { fg: "#d4dbe6", bg: "rgba(212,219,230,0.05)", edge: "rgba(212,219,230,0.16)", glow: "rgba(212,219,230,0.18)" },
  cyan:    { fg: "#7dd3df", bg: "rgba(125,211,223,0.10)", edge: "rgba(125,211,223,0.24)", glow: "rgba(125,211,223,0.30)" },
};

// OP9: type tiles split into two semantic sections.
// 「核心」 = first-class entities that exist regardless of user skills
//   (event / contact / file — backed by their own tables).
// 「我的技能」 = user-extensible skill assets (todo / expense / idea /
//   notes / misc) — these evolve over time as user adds new skill types
//   via the AddSkillWizard. The 添加新技能 tile sits at the end of this
//   row so the "I can add more" affordance is visible inline.
const CORE_TILES: TileKind[] = [
  { key: "event",        to: "/library/event",        label: "事件", icon: "●",  accent: "purple"  },
  { key: "contact",      to: "/library/contact",      label: "名片", icon: "◯",  accent: "neutral" },
  { key: "file",         to: "/library/file",         label: "文件", icon: "♪",  accent: "cyan"    },
  // 外部引用 — pointers to things created in third-party systems (Notion /
  // 钉钉 / Google Calendar) via the task-skill MCP. A first-class entity like
  // event/contact/file, so it lives here in 常驻 rather than the skills grid.
  { key: "external_ref", to: "/library/external_ref", label: "外部", icon: "🔗", accent: "blue"    },
];

// render_spec.accent_color → LibAccent, for the core-tile fallback.
const RENDER_TO_LIB: Record<AccentColor, LibAccent> = {
  blue: "blue", amber: "amber", green: "green", purple: "purple",
  red: "amber", gray: "neutral", neutral: "neutral",
};

// SkillsGrid uses a slimmer accent palette; map the registry's render_spec
// colors into it. red/gray fold into amber/neutral.
const RENDER_TO_GRID: Record<AccentColor, TileAccent> = {
  blue: "blue", amber: "amber", green: "green", purple: "purple",
  red: "amber", gray: "neutral", neutral: "neutral",
};

// Seeded canonical skills that we surface but DON'T allow deletion of —
// these are the framework's default skill kinds. User-created skills (跑步
// / 读书 / habit / ...) are deletable.
const PROTECTED_SKILL_NAMES = new Set([
  "todo", "idea", "expense", "notes", "misc",
]);

// System skills (not user-facing) — never shown in the SKILLS grid.
const HIDDEN_SKILL_NAMES = new Set(["external_ref", "qa", "contact"]);
// (`contact` is a system skill but its real list lives in the CORE 名片 tile.)

export function CategoryList() {
  const { skills } = useSkillRegistry();

  // Pull everything in parallel; SWR dedupes across the hub + drill-down pages.
  const allAssets = useSWR<AssetsResponse>("/api/assets?limit=500", swrFetcher);
  const events    = useSWR<EventsResponse>("/api/events", swrFetcher);
  const files     = useSWR<FilesResponse>("/api/files", swrFetcher);
  const contacts  = useSWR<ContactsResponse>("/api/contacts", swrFetcher);

  const assets = allAssets.data?.assets ?? [];

  // Total count for the caps mono subtitle. Sums everything visible in the
  // hub (asset-backed skills + first-class entities).
  const totalCount =
    assets.length + (events.data?.events?.length ?? 0) +
    (files.data?.files?.length ?? 0) + (contacts.data?.contacts?.length ?? 0);

  // Build the 「最近」 cross-type list — newest 5 across asset / event / file
  // (contacts aren't time-stamped meaningfully so they don't appear in this
  // "recent activity" list; they're reachable via the 名片 tile).
  const recent = buildRecent({
    assets, events: events.data?.events ?? [], files: files.data?.files ?? [],
    bySkillIcon: iconMap(skills),
  }, 8);

  // SKILLS tiles = every registered user skill (seeded defaults + anything
  // created via AddSkillWizard), ordered by user_skills.position so drag-to-
  // reorder persists. Backend already returns sorted; we re-sort defensively
  // so a stale cache doesn't show jitter.
  const gridTiles: SkillTileData[] = skills
    .filter((s) => s.render_spec && !HIDDEN_SKILL_NAMES.has(s.name))
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    .map((s) => ({
      user_skill_id: s.user_skill_id,
      name:          s.name,
      label:         s.display_name || s.name,
      icon:          s.render_spec?.icon ?? "◇",
      accent:        RENDER_TO_GRID[s.render_spec?.accent_color ?? "neutral"] ?? "neutral",
      count:         countFor(s.name, { assets, events: events.data?.events, files: files.data?.files, contacts: contacts.data?.contacts }),
      preview:       previewFor(s.name, { assets, events: events.data?.events, files: files.data?.files, contacts: contacts.data?.contacts }),
      deletable:     !PROTECTED_SKILL_NAMES.has(s.name),
    }));

  return (
    <div
      className="flex flex-col h-full"
      style={{
        background:
          "radial-gradient(800px 500px at 20% -10%, rgba(111,158,255,0.10), transparent 60%), #06070d",
        color: "#d4dbe6",
        fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      }}
    >
      {/* ── Hero header: 大字 + caps mono total + 搜索 ───────────────── */}
      <header
        className="flex items-baseline justify-between shrink-0"
        style={{ padding: "8px 22px 14px" }}
      >
        <div>
          <h1
            className="font-display"
            style={{
              fontSize: 26, fontWeight: 700, color: "#f4f7fb",
              letterSpacing: "-0.02em",
            }}
          >
            资产库
          </h1>
          <div
            className="font-mono"
            style={{
              fontSize: 10.5, color: "rgba(255,255,255,0.45)",
              letterSpacing: "0.16em", marginTop: 4,
            }}
          >
            {totalCount} ITEMS · LAST 30D
          </div>
        </div>
        <button
          type="button"
          className="font-mono"
          style={{
            width: 32, height: 32, borderRadius: 999,
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.08)",
            color: "rgba(255,255,255,0.70)", fontSize: 13, cursor: "pointer",
          }}
          title="搜索"
        >
          ⌕
        </button>
      </header>

      {/* ── Scrollable body: tiles + 最近 + 扩展 ───────────────────── */}
      <div
        className="flex-1 overflow-y-auto eu-noscroll"
        // Bottom padding clears the floating dock (h-56 + 16px offset + glow)
        // so the last 最近 card can scroll fully into view instead of sitting
        // permanently half-hidden behind the dock.
        style={{ padding: "0 16px", paddingBottom: "calc(env(safe-area-inset-bottom) + 104px)" }}
      >
        {/* OP9: two semantic sections — 核心 (常驻 first-class entities)
            and 我的技能 (user-evolvable skill assets). Both use 3-col grid
            so a 393px iPhone frame fits 3 tiles per row neatly. The
            添加新技能 tile lives at the end of 技能 inline as the natural
            "extend" affordance. */}
        <SectionLabel>常驻 · PERMANENT</SectionLabel>
        <div
          className="grid grid-cols-4 gap-2"
          style={{ margin: "6px 0 16px" }}
        >
          {CORE_TILES.map((t) => (
            <TypeTile
              key={t.key}
              tile={t}
              count={countFor(t.key, { assets, events: events.data?.events, files: files.data?.files, contacts: contacts.data?.contacts })}
              preview={previewFor(t.key, { assets, events: events.data?.events, files: files.data?.files, contacts: contacts.data?.contacts })}
            />
          ))}
        </div>

        <SectionLabel>启用的技能 · SKILLS</SectionLabel>
        <SkillsGrid tiles={gridTiles} />

        <SectionLabel>最近 · RECENT</SectionLabel>

        {/* Cross-type latest activity, grouped by day (今天 / 昨天 / M月D日) so a
            multi-day glance is scannable instead of one flat undifferentiated run. */}
        {recent.length === 0 ? (
          <div
            className="font-mono"
            style={{ fontSize: 11, color: "rgba(255,255,255,0.30)", padding: "10px 0" }}
          >
            还没有资产 — 用底部 + 或 🎙 创建
          </div>
        ) : (
          groupByDay(recent).map(([dayKey, items]) => (
            <div key={dayKey} className="flex flex-col gap-2" style={{ marginBottom: 10 }}>
              <DayHeader label={dayHeaderLabel(dayKey)} />
              {items.map((r) => <RecentCard key={r.id} item={r} />)}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

/* ── Section divider — caps mono label + thin rule on the right ─────── */

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2.5" style={{ marginTop: 6 }}>
      <span
        className="font-mono"
        style={{
          fontSize: 10.5, letterSpacing: "0.22em",
          color: "rgba(255,255,255,0.55)", fontWeight: 600,
        }}
      >
        {children}
      </span>
      <span style={{ flex: 1, height: 1, background: "rgba(255,255,255,0.05)" }} />
    </div>
  );
}

/* ── 最近 day-group header — lighter than SectionLabel (a sub-label, not a
   section divider): caps mono, no rule, sits above each day's cards. ── */
function DayHeader({ label }: { label: string }) {
  return (
    <div
      className="font-mono"
      style={{
        fontSize: 10, letterSpacing: "0.14em",
        color: "rgba(255,255,255,0.42)", fontWeight: 600,
        marginTop: 4,
      }}
    >
      {label}
    </div>
  );
}

/* ── Tile + RecentCard subcomponents ──────────────────────────────────── */

// Compact entry tile per the Mobile-Redesign spec (library.jsx EntryRow) — the
// user flagged the old blocks as "太大了". Small: icon + label + count, ~78px,
// no preview line.
function TypeTile({
  tile, count,
}: { tile: TileKind; count: number; preview?: string }) {
  const ac = LIB_ACCENT[tile.accent];
  return (
    <Link
      to={tile.to}
      className="flex flex-col text-left active:scale-95"
      style={{
        gap: 6,
        padding: "10px 10px", borderRadius: 12,
        background: ac.bg, border: `1px solid ${ac.edge}`,
        minHeight: 78,
        transition: "all 200ms cubic-bezier(.2,.7,.3,1)",
      }}
    >
      <span
        className="font-mono"
        style={{
          width: 28, height: 28, borderRadius: 8,
          background: `linear-gradient(140deg, ${ac.bg}, rgba(255,255,255,0.02))`,
          border: `1px solid ${ac.edge}`,
          boxShadow: `inset 0 0 12px ${ac.glow}`,
          display: "flex", alignItems: "center", justifyContent: "center",
          color: ac.fg, fontSize: 13, fontWeight: 600,
        }}
      >
        {tile.icon}
      </span>
      <div className="flex items-baseline justify-between" style={{ marginTop: "auto" }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: "#f4f7fb" }}>{tile.label}</span>
        <span className="font-mono" style={{ fontSize: 13, fontWeight: 600, color: ac.fg }}>{count}</span>
      </div>
    </Link>
  );
}

interface RecentItem {
  id:       string;
  to:       string;
  accent:   LibAccent;
  icon:     string;
  kindCaps: string;
  title:    string;
  sub:      string;
  hasSource: boolean;
  /** Local day key (YYYY-MM-DD) of the item's timestamp — drives 最近 day grouping. */
  dayKey:   string;
  /** When the source is an event, render via EventCard. */
  event?:   Event;
  /** OP2: when the source is an asset, render via SkillCard for visual
   *  uniformity with /library and chat. */
  asset?:   Asset;
}

function RecentCard({ item }: { item: RecentItem }) {
  const navigate = useNavigate();
  const { bySkill } = useSkillRegistry();
  const toggleTodo = useToggleTodo();

  // OP2: route events through EventCard, asset-backed items through
  // SkillCard. Both are the universal "list-item" container — Library
  // Recent now matches DayDetail / Chat visually field-for-field.
  if (item.event) {
    return (
      <EventCard
        event={item.event}
        onClick={() => navigate(item.to)}
        createdMeta={relativeTime(item.event.created_at)}
      />
    );
  }
  if (item.asset) {
    const skill = bySkill.get(item.asset.user_skill_name);
    const card = buildCard({
      payload: item.asset.payload,
      spec:    skill?.render_spec ?? null,
      assetId: item.asset.id,
      cardType: item.asset.user_skill_name,
      displayName: skill?.display_name ?? item.asset.user_skill_name,
    });
    // OP8: 最近 list is sorted by created_at desc — surface that as a
    // meta chip so the sort dimension is visible (cards otherwise show
    // skill-natural fields like due_date/expense.created, which made
    // the order look random to the user).
    card.metaFields = [
      ...card.metaFields,
      { field: "created_at", value: relativeTime(item.asset.created_at) },
    ];
    return (
      <SkillCard
        data={card}
        // 最近 is a cross-type list — force the compact horizontal layout so
        // every row is the same height. Without this, skills whose render_spec
        // uses `stacked` (e.g. 想法, with a 3-line body) render ~50px taller
        // than expense/event rows, making the list look ragged. Each skill's
        // natural layout still applies inside its own category view.
        layoutOverride="horizontal"
        onClick={() => navigate(item.to)}
        onToggleCheck={card.checkDone !== undefined && item.asset
          ? (next) => toggleTodo(item.asset!.id, next)
          : undefined}
      />
    );
  }

  // File / non-asset fallback: keep the bespoke compact card below.
  const ac = LIB_ACCENT[item.accent];
  return (
    <Link
      to={item.to}
      className="flex flex-col text-left"
      style={{
        padding: "12px 14px", borderRadius: 14,
        background: ac.bg, border: `1px solid ${ac.edge}`,
        gap: 6,
        transition: "all 280ms cubic-bezier(.2,.7,.3,1)",
      }}
    >
      <div className="flex items-center" style={{ gap: 8 }}>
        <span
          className="font-mono"
          style={{
            width: 22, height: 22, borderRadius: 6,
            background: "rgba(0,0,0,0.20)",
            border: `1px solid ${ac.edge}`,
            display: "flex", alignItems: "center", justifyContent: "center",
            color: ac.fg, fontSize: 12,
          }}
        >
          {item.icon}
        </span>
        <span
          className="font-mono"
          style={{
            fontSize: 9.5, letterSpacing: "0.18em",
            color: ac.fg, fontWeight: 600,
          }}
        >
          {item.kindCaps}
        </span>
        {item.hasSource && (
          <span style={{ marginLeft: "auto", fontSize: 11, color: "rgba(164,194,255,0.65)" }}>♪</span>
        )}
      </div>
      <div
        style={{
          fontSize: 14, fontWeight: 600, color: "#f4f7fb",
          letterSpacing: "-0.005em",
          overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
        }}
      >
        {item.title}
      </div>
      <div
        className="font-mono"
        style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", letterSpacing: "0.06em" }}
      >
        {item.sub}
      </div>
    </Link>
  );
}

/* (Old AddSkillTile / per-cap state removed — handled inside SkillsGrid +
   backend USER_SKILL_CAP=9. The plus tile and the cap UI live in
   SkillsGrid.tsx now so they share the same long-press/edit-mode state.) */

/* ── Data helpers ─────────────────────────────────────────────────────── */

function iconMap(skills: ReturnType<typeof useSkillRegistry>["skills"]) {
  const m = new Map<string, string>();
  for (const s of skills) {
    if (s.render_spec?.icon) m.set(s.name, s.render_spec.icon);
  }
  return m;
}

function countFor(
  key: string,
  d: { assets: Asset[]; events?: Event[]; files?: FileRow[]; contacts?: ContactsResponse["contacts"] },
): number {
  if (key === "event")   return d.events?.length ?? 0;
  if (key === "file")    return d.files?.length  ?? 0;
  if (key === "contact") return d.contacts?.length ?? 0;
  return d.assets.filter((a) => a.user_skill_name === key).length;
}

function previewFor(
  key: string,
  d: { assets: Asset[]; events?: Event[]; files?: FileRow[]; contacts?: ContactsResponse["contacts"] },
): string {
  if (key === "event") {
    const e = d.events?.[0];
    if (!e) return "";
    const d2 = new Date(e.start_at);
    return `${e.title} · ${d2.getMonth() + 1}月${d2.getDate()}`;
  }
  if (key === "file") {
    const f = d.files?.[0];
    if (!f) return "";
    const tag = f.source_tag === "flash" ? "闪念"
              : f.source_tag === "meeting" ? "会议" : "上传";
    return `${tag} · ${f.duration_sec ? `${Math.round(f.duration_sec)}s` : ""}`.trim();
  }
  if (key === "contact") {
    const c = d.contacts?.[0];
    if (!c) return "";
    return c.company ? `${c.name} · ${c.company}` : c.name;
  }
  // Asset-backed skills — first row's title-ish field. Fall back to "" (not
  // the machine name) so AI-created skills with custom fields like 跑步记录
  // (distance/pace/feeling) don't surface a raw "running" preview string.
  const a = d.assets.find((x) => x.user_skill_name === key);
  if (!a) return "";
  const p = a.payload as { content?: unknown; title?: unknown; name?: unknown };
  const v = p.content ?? p.title ?? p.name;
  return v != null && v !== "" ? String(v) : "";
}

/* ── 最近 list builder ──────────────────────────────────────────────── */

function buildRecent(
  d: {
    assets: Asset[]; events: Event[]; files: FileRow[];
    bySkillIcon: Map<string, string>;
  },
  limit: number,
): RecentItem[] {
  const merged: Array<RecentItem & { _ts: number }> = [];

  for (const a of d.assets) {
    const skillName = a.user_skill_name;
    const tileAccent = accentForSkill(skillName);
    const icon = d.bySkillIcon.get(skillName) ?? "·";
    const p = a.payload as { content?: unknown; title?: unknown; name?: unknown };
    merged.push({
      _ts:      +new Date(a.created_at),
      id:       `asset-${a.id}`,
      to:       `/library/${skillName}`,
      accent:   tileAccent,
      icon,
      kindCaps: skillName.toUpperCase(),
      title:    String(p.content ?? p.title ?? p.name ?? skillName),
      sub:      relativeTime(a.created_at),
      hasSource: !!a.source_input_turn_id,
      dayKey:   localDayKey(a.created_at),
      asset:    a,   // OP2: enables SkillCard rendering
    });
  }
  for (const e of d.events) {
    merged.push({
      _ts:      +new Date(e.created_at),
      id:       `event-${e.event_id}`,
      to:       `/library/event`,
      accent:   "purple",
      icon:     "●",
      kindCaps: "EVENT",
      title:    e.title,
      sub:      formatStart(e.start_at, e.all_day),
      hasSource: !!e.source_input_turn_id,
      dayKey:   localDayKey(e.created_at),
      event:    e,   // for unified EventCard rendering
    });
  }
  for (const f of d.files) {
    merged.push({
      _ts:      +new Date(f.created_at),
      id:       `file-${f.id}`,
      to:       `/library/file`,
      accent:   "cyan",
      icon:     "♪",
      kindCaps: (f.source_tag ?? "FILE").toUpperCase(),
      title:    `${f.source_tag === "flash" ? "闪念录音" : f.source_tag === "meeting" ? "会议录音" : "文件"}`,
      sub:      `${f.duration_sec ? `${Math.round(f.duration_sec)}s · ` : ""}${relativeTime(f.created_at)}`,
      hasSource: false,
      dayKey:   localDayKey(f.created_at),
    });
  }

  merged.sort((a, b) => b._ts - a._ts);
  return merged.slice(0, limit).map(({ _ts: _, ...rest }) => rest);
}

function accentForSkill(name: string): LibAccent {
  switch (name) {
    case "todo":    return "blue";
    case "idea":    return "amber";
    case "expense": return "green";
    case "contact": return "neutral";
    case "notes":   return "blue";
    default:        return "neutral";
  }
}

/** Local day key (YYYY-MM-DD) — for grouping 最近 by calendar day. */
function localDayKey(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** Human day header: 今天 / 昨天 / M月D日 (older). */
function dayHeaderLabel(dayKey: string): string {
  const today = localDayKey(new Date().toISOString());
  if (dayKey === today) return "今天";
  const y = new Date();
  y.setDate(y.getDate() - 1);
  if (dayKey === localDayKey(y.toISOString())) return "昨天";
  const [, mo, da] = dayKey.split("-").map(Number);
  return `${mo}月${da}日`;
}

/** Group already-sorted (desc) recent items into [dayKey, items] runs,
 *  preserving the sort so day groups come out newest-first. */
function groupByDay(items: RecentItem[]): Array<[string, RecentItem[]]> {
  const out: Array<[string, RecentItem[]]> = [];
  const idx = new Map<string, RecentItem[]>();
  for (const it of items) {
    let arr = idx.get(it.dayKey);
    if (!arr) {
      arr = [];
      idx.set(it.dayKey, arr);
      out.push([it.dayKey, arr]);
    }
    arr.push(it);
  }
  return out;
}

function relativeTime(iso: string): string {
  const t = +new Date(iso);
  const now = Date.now();
  const diffSec = Math.max(0, Math.floor((now - t) / 1000));
  if (diffSec < 60)        return "刚刚";
  if (diffSec < 3600)      return `${Math.floor(diffSec / 60)} 分钟前`;
  if (diffSec < 86400)     return `${Math.floor(diffSec / 3600)} 小时前`;
  if (diffSec < 86400 * 7) return `${Math.floor(diffSec / 86400)} 天前`;
  const d = new Date(iso);
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

function formatStart(iso: string, allDay: boolean): string {
  const d = new Date(iso);
  if (allDay) return `${d.getMonth() + 1}月${d.getDate()}日 · 全天`;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getMonth() + 1}月${d.getDate()}日 ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
