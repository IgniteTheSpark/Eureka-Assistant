import { useState } from "react";
import { CalendarDays, Grid3x3, Loader2, Mic, Plus, Send, Sparkles, X } from "lucide-react";
import { useNavigate } from "react-router-dom";

import { CreateAssetMenu } from "@/components/library/CreateAssetMenu";
import { AssetCardInChat } from "@/components/chat/AssetCardInChat";
import { useFlashCapture } from "@/hooks/useFlashCapture";
import { openSession } from "@/hooks/useSessions";
import { useAgentTarget, useIsAnyModalOpen, useModalMount } from "@/context/ModalContext";

/**
 * FloatingDock — global floating action capsule, replaces the old bottom
 * TabBar. Always present (across all pages), floats above content with margin
 * from screen edges.
 *
 * Items, left → right:
 *   1. Today      — calendar icon with today's date → /calendar
 *   2. Library    — grid icon → /library
 *   ──── divider ────
 *   3. Quick create — (+) → CreateAssetMenu popover (M1 wires this up)
 *   4. Flash      — mic → full-screen capture sheet (was FlashFab in M0)
 *   ──── divider ────
 *   5. Agent      — ✨ Agent pill (purple gradient) → /chat
 *
 * Per Phase D spec amendment (2026-05-26): no current-page active state on
 * the dock — TopBar already shows the page title; dock is pure shortcut bar.
 */
export function FloatingDock() {
  const navigate = useNavigate();
  const [flashOpen, setFlashOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  // Hide the dock whenever any modal is mounted — backdrop-blur + saturated
  // dock items would otherwise bleed through any z-50 backdrop overlay.
  const hidden = useIsAnyModalOpen();
  const { agentTarget } = useAgentTarget();

  /**
   * Agent entry. When a detail view registered an agentTarget (asset/event/
   * contact), peek for an existing bound session:
   *   - exists  → open it directly (instant reopen of the same thread).
   *   - missing → navigate to /chat with `pendingSubject` in router state;
   *               ChatPage creates the session JIT on first send so a stray
   *               tap doesn't litter sidebar history (#5, May audit).
   * No agentTarget → open last/empty /chat.
   *
   * Detail pages no longer need their own 「在 chat 里讨论」 button — the
   * global dock is the agent entry.
   */
  async function openAgent() {
    if (!agentTarget) {
      navigate("/chat");
      return;
    }
    try {
      const { sessionId } = await openSession({
        subject: agentTarget.subject,
        peekOnly: true,
      });
      if (sessionId) {
        // Existing thread — open it directly.
        window.localStorage.setItem("eureka:active_chat_session", sessionId);
        navigate("/chat");
      } else {
        // No thread yet — defer creation to first send. /chat reads the
        // hint from router state and binds the subject in the topic bar.
        navigate("/chat", {
          state: {
            pendingSubject: agentTarget.subject,
            pendingLabel:   agentTarget.label,
          },
        });
      }
    } catch {
      navigate("/chat");
    }
  }

  return (
    <>
      {/* 背透 fix — the dock is the same glass everywhere, but on flat near-black
          pages (#06070d) the glass has nothing to transmit so it reads as a
          solid 背景板; in DayDetail it sits over a blue gradient and reads as
          real 背透. This ambient brand glow gives the glass something to pick
          up on every page → the dock now blends like it does in DayDetail.
          z-[55]: above page content, below the z-[60] nav so the dock's
          backdrop-blur samples it. Hides/fades together with the dock. */}
      <div
        aria-hidden="true"
        className={[
          "fixed inset-x-0 bottom-0 z-[55] pointer-events-none",
          "transition-opacity duration-eu-fast ease-eu-out",
          hidden ? "opacity-0" : "opacity-100",
        ].join(" ")}
        style={{
          height: 220,
          background:
            "radial-gradient(120% 100% at 50% 120%, rgba(111,158,255,0.34) 0%, rgba(111,158,255,0.12) 38%, rgba(6,7,13,0) 72%)",
        }}
      />

      {/* OP10: back to a single floating capsule (premium version). The
          earlier 5-separate-chips / transparent-ring iterations felt
          unanchored. This is a solid dark-glass capsule that hovers above
          the page — z-[60] so it stays above page-like modals (DayDetail)
          that opt to keep the dock. backdrop-blur kept but the bg is solid
          enough (92%) that the old saturated-bleed issue doesn't recur. */}
      <nav
        aria-label="主要操作"
        aria-hidden={hidden}
        className={[
          "fixed bottom-[calc(env(safe-area-inset-bottom)+1rem)]",
          "left-1/2 -translate-x-1/2 z-[60]",
          "flex items-center gap-1",
          "h-14 pl-2 pr-2 rounded-eu-full",
          // 真正背透 — 设计语言统一用 blur(10px) + 轻阴影。之前 blur-2xl(40px) +
          // 重暗阴影把背后内容糊成一坨纯暗,看起来像实心胶囊。改成 blur-md(12px) +
          // saturate 让背后的蓝/绿瓦片透出颜色,轻阴影避免“悬浮实心块”观感。
          "bg-white/[0.05] backdrop-blur-md backdrop-saturate-150",
          "border border-white/[0.08]",
          "shadow-[0_6px_24px_rgba(0,0,0,0.28),inset_0_1px_0_rgba(255,255,255,0.10)]",
          "transition-all duration-eu-fast ease-eu-out",
          hidden ? "opacity-0 pointer-events-none translate-y-3" : "",
        ].join(" ")}
      >
        <DockIcon ariaLabel="日历" onClick={() => navigate("/calendar")}>
          <CalendarDays size={19} strokeWidth={1.7} />
        </DockIcon>

        <DockIcon ariaLabel="资产库" onClick={() => navigate("/library")}>
          <Grid3x3 size={18} strokeWidth={1.85} />
        </DockIcon>

        <Divider />

        <DockIcon ariaLabel="快创" onClick={() => setCreateOpen(true)}>
          <Plus size={20} strokeWidth={2.1} />
        </DockIcon>

        <DockIcon ariaLabel="闪念输入" onClick={() => setFlashOpen(true)}>
          <Mic size={18} strokeWidth={1.85} />
        </DockIcon>

        <Divider />

        {/* Agent — purple gradient pill, brand entry */}
        <button
          type="button"
          aria-label="Agent 对话"
          onClick={openAgent}
          className={[
            "h-10 pl-3 pr-4 ml-0.5 rounded-eu-full",
            "bg-gradient-to-br from-eu-accent-purple-solid to-eu-accent-blue-solid",
            "text-white font-medium text-eu-sm",
            "flex items-center gap-1.5",
            "shadow-[0_6px_20px_rgba(111,158,255,0.4)]",
            "transition-all duration-eu-fast ease-eu-out",
            "active:scale-95",
          ].join(" ")}
        >
          <Sparkles size={14} strokeWidth={2} />
          Agent
        </button>
      </nav>

      {flashOpen && (
        <FlashSheet onClose={() => setFlashOpen(false)} />
      )}
      <CreateAssetMenu open={createOpen} onClose={() => setCreateOpen(false)} />
    </>
  );
}

/* ── Internal pieces ───────────────────────────────────────────────────── */

interface DockIconProps {
  ariaLabel: string;
  onClick: () => void;
  children: React.ReactNode;
}

/** DockIcon — a plain icon button inside the capsule (OP10). No per-icon
 *  plate; the capsule is the container. */
function DockIcon({ ariaLabel, onClick, children }: DockIconProps) {
  return (
    <button
      type="button"
      aria-label={ariaLabel}
      onClick={onClick}
      className={[
        "h-10 w-10 rounded-eu-full",
        "flex items-center justify-center",
        "text-eu-text-mid hover:text-eu-text-hi hover:bg-white/5",
        "transition-all duration-eu-fast ease-eu-out",
        "active:scale-90",
      ].join(" ")}
    >
      {children}
    </button>
  );
}

function Divider() {
  return <div aria-hidden="true" className="h-6 w-px bg-white/10 mx-0.5" />;
}

/* ── Flash sheet (was FlashFab) ────────────────────────────────────────── */

function FlashSheet({ onClose }: { onClose: () => void }) {
  useModalMount();
  const [text, setText] = useState("");
  const { capture, submitting, lastResult, error, reset } = useFlashCapture();

  async function submit() {
    if (!text.trim() || submitting) return;
    const result = await capture(text);
    if (result?.ok && !result.error) {
      setText("");
      // Keep sheet open so user sees the reply + cards. Close on tap-out or
      // explicit close. (If they want to flash again, just type.)
    }
  }

  function handleClose() {
    reset();
    setText("");
    onClose();
  }

  const hasResult = lastResult && (lastResult.reply || lastResult.cards.length > 0 || lastResult.summary);

  return (
    <div
      // Heavy backdrop so FloatingDock items don't bleed into the sheet.
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md eu-fade-in"
      onClick={handleClose}
    >
      <div
        className={[
          // VF: bottom sheet only (phone-frame is mobile-shaped).
          "fixed inset-x-0 bottom-0",
          "bg-eu-surface-raised border-t border-eu-border rounded-t-eu-xl",
          "eu-sheet-up",
          "p-eu-lg pb-safe flex flex-col gap-eu-md shadow-eu-lg",
          "max-h-[88vh] overflow-y-auto eu-noscroll",
        ].join(" ")}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h2 className="font-display text-eu-lg text-eu-text-hi">闪念</h2>
          <button
            type="button"
            aria-label="关闭"
            onClick={handleClose}
            className="p-1 rounded-eu-sm hover:bg-eu-surface-hover text-eu-text-mid"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </div>
        <textarea
          autoFocus
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) submit();
          }}
          placeholder="说点什么…(⌘/Ctrl+Enter 提交)"
          rows={3}
          disabled={submitting}
          className={[
            "w-full resize-none",
            "bg-eu-surface border border-eu-border rounded-eu-md",
            "p-eu-md text-eu-base text-eu-text",
            "placeholder:text-eu-text-muted",
            "focus:outline-none focus:border-eu-brand",
            "disabled:opacity-50",
            "transition-colors duration-eu-fast",
          ].join(" ")}
        />

        <div className="flex justify-between items-center gap-eu-sm">
          <div className="text-eu-xs text-eu-text-lo font-mono">
            {submitting
              ? "AI 处理中…(约 15-30 秒)"
              : hasResult ? "继续打字开新一条" : "⌘/Ctrl+Enter 也行"}
          </div>
          <div className="flex gap-eu-sm">
            <button
              type="button"
              onClick={handleClose}
              className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi"
            >
              关闭
            </button>
            <button
              type="button"
              onClick={submit}
              disabled={!text.trim() || submitting}
              className={[
                "px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                "bg-eu-brand text-white",
                "hover:bg-eu-brand-hi disabled:opacity-50 disabled:cursor-not-allowed",
                "transition-colors duration-eu-fast flex items-center gap-1.5",
              ].join(" ")}
            >
              {submitting
                ? <Loader2 size={14} strokeWidth={2} className="animate-spin" />
                : <Send size={14} strokeWidth={2} />}
              {submitting ? "处理中" : "提交"}
            </button>
          </div>
        </div>

        {error && !lastResult && (
          <div className="text-eu-sm text-eu-accent-red-fg bg-eu-accent-red-bg border border-eu-accent-red-edge rounded-eu-md px-eu-md py-eu-sm">
            {error}
          </div>
        )}

        {lastResult && (
          <FlashResultPanel result={lastResult} />
        )}
      </div>
    </div>
  );
}

/**
 * FlashResultPanel — shows the backend's reply / summary / cards after a
 * successful flash submit.
 */
function FlashResultPanel({ result }: { result: ReturnType<typeof useFlashCapture>["lastResult"] }) {
  if (!result) return null;
  return (
    <div className="border-t border-eu-rule pt-eu-md flex flex-col gap-eu-sm">
      {result.reply && (
        <div className="text-eu-base text-eu-text whitespace-pre-wrap leading-relaxed">
          {result.reply}
        </div>
      )}
      {result.summary && !result.reply && (
        <div className="text-eu-sm text-eu-text-mid">{result.summary}</div>
      )}
      {result.cards.length > 0 && (
        <div className="flex flex-col gap-eu-sm">
          {result.cards.map((c, i) => (
            <AssetCardInChat
              key={i}
              data={c as unknown as Record<string, unknown>}
            />
          ))}
        </div>
      )}
      {result.error && (
        <div className="text-eu-xs text-eu-accent-red-fg font-mono">
          ⚠ {result.error}
        </div>
      )}
    </div>
  );
}

