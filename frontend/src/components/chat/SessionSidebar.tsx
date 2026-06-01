import { MessageCircle, Mic, Plus, X } from "lucide-react";

import { useSessions } from "@/hooks/useSessions";
import type { Session } from "@/lib/types";

/**
 * SessionSidebar — Claude-style chat history.
 *
 * VF (iPhone frame): the app is now always 393px wide (PhoneFrame), so the
 * old desktop-persistent-260px-column variant is gone. Sidebar is always
 * a slide-in drawer triggered by the「☰ 历史」 button in ChatPage's top
 * nav. This frees the full chat width for messages.
 *
 * Lists chat + flash sessions newest first. Tapping switches active session;
 * the「新建对话」button clears the active session_id so the next send opens
 * a fresh chat.
 *
 * NB: session list isn't paginated yet; backend returns up to 30 by default.
 * For demo scale that's fine — when needed, add infinite-scroll later.
 */

interface SessionSidebarProps {
  activeId: string | null;
  onSelect: (id: string | null) => void;
  open: boolean;
  onClose: () => void;
}

export function SessionSidebar({ activeId, onSelect, open, onClose }: SessionSidebarProps) {
  return (
    <div
      className={[
        "fixed inset-0 z-50",
        open ? "pointer-events-auto" : "pointer-events-none",
      ].join(" ")}
      aria-hidden={!open}
    >
      {/* Backdrop */}
      <div
        className={[
          "absolute inset-0 bg-eu-bg/85 backdrop-blur-md",
          "transition-opacity duration-eu-fast",
          open ? "opacity-100" : "opacity-0",
        ].join(" ")}
        onClick={onClose}
      />
      {/* Drawer */}
      <aside
        className={[
          "absolute inset-y-0 left-0 w-[80%] max-w-[300px]",
          "bg-eu-surface-raised border-r border-eu-border",
          "shadow-eu-lg flex flex-col pt-safe",
          "transition-transform duration-[200ms] ease-eu-out",
          open ? "translate-x-0" : "-translate-x-full",
        ].join(" ")}
      >
        <div className="flex items-center justify-between px-eu-md py-eu-sm border-b border-eu-rule">
          <span className="font-display text-eu-md text-eu-text-hi">对话历史</span>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="p-1 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </div>
        <SidebarInner
          activeId={activeId}
          onSelect={(id) => { onSelect(id); onClose(); }}
        />
      </aside>
    </div>
  );
}

function SidebarInner({
  activeId, onSelect,
}: { activeId: string | null; onSelect: (id: string | null) => void }) {
  const { sessions, isLoading } = useSessions({ limit: 50 });

  return (
    <div className="flex flex-col h-full min-h-0">
      <div className="px-eu-md py-eu-md">
        <button
          type="button"
          onClick={() => onSelect(null)}
          className={[
            "w-full flex items-center justify-center gap-1.5",
            "px-eu-md py-eu-sm rounded-eu-md",
            "bg-eu-brand text-white text-eu-sm font-medium",
            "hover:bg-eu-brand-hi transition-colors duration-eu-fast",
          ].join(" ")}
        >
          <Plus size={14} strokeWidth={2} />
          新建对话
        </button>
      </div>

      <div className="flex-1 overflow-y-auto eu-noscroll px-eu-sm pb-eu-md">
        {isLoading && (
          <div className="text-eu-xs text-eu-text-lo px-eu-sm py-eu-sm font-mono">加载中…</div>
        )}
        {!isLoading && sessions.length === 0 && (
          <div className="text-eu-sm text-eu-text-lo px-eu-sm py-eu-sm">还没有对话</div>
        )}

        {sessions.map((s) => (
          <SessionRow
            key={s.id}
            session={s}
            active={activeId === s.id}
            onClick={() => onSelect(s.id)}
          />
        ))}
      </div>
    </div>
  );
}

function SessionRow({
  session, active, onClick,
}: { session: Session; active: boolean; onClick: () => void }) {
  const Icon = session.session_type === "flash" ? Mic : MessageCircle;
  const dateLabel = session.date ?? formatRelativeDate(session.created_at);

  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "w-full flex items-start gap-eu-sm px-eu-sm py-eu-sm rounded-eu-md text-left",
        "transition-colors duration-eu-fast",
        active
          ? "bg-eu-brand-faint text-eu-text-hi"
          : "text-eu-text-mid hover:bg-eu-surface-hover hover:text-eu-text-hi",
      ].join(" ")}
    >
      <Icon size={14} strokeWidth={1.75} className="shrink-0 mt-0.5" />
      <div className="flex-1 min-w-0">
        <div className="text-eu-sm truncate">
          {session.title || "(无标题)"}
        </div>
        <div className="text-eu-xs text-eu-text-lo font-mono mt-0.5">
          {session.session_type} · {dateLabel}
        </div>
      </div>
    </button>
  );
}

function formatRelativeDate(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso.slice(0, 10);
    const now = new Date();
    const today = now.toDateString();
    const yesterday = new Date(now.getTime() - 86_400_000).toDateString();
    if (d.toDateString() === today) {
      return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
    }
    if (d.toDateString() === yesterday) return "昨天";
    return `${d.getMonth() + 1}/${d.getDate()}`;
  } catch { return iso.slice(0, 10); }
}
