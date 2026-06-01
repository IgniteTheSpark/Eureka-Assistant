import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";

/**
 * ModalContext — tracks how many full-screen modals are currently mounted.
 *
 * Why: FloatingDock uses `backdrop-blur-md` which creates a compositing
 * layer — even when a higher z-index modal backdrop covers it, Chromium can
 * render the dock through it (saturated dock items like the Agent pill + red
 * date badge bleed through). The reliable fix is to remove the dock from the
 * scene while any modal is open.
 *
 * Every full-screen modal (CreateAssetMenu, FlashSheet, AssetDetailDrawer)
 * calls `useModalMount()` and the dock subscribes via `useIsAnyModalOpen()`.
 */

/**
 * AgentTarget — when an asset/event/contact detail is open, it registers the
 * subject here so the GLOBAL dock's Agent button enters that thing's bound
 * session directly (instead of a generic /chat). Per user: the detail page no
 * longer needs its own 「在 chat 里讨论」 — the dock IS the agent entry.
 */
export interface AgentTarget {
  subject: { type: "asset" | "event" | "contact" | "file"; id: string };
  label: string;
}

interface ModalContextValue {
  count: number;
  register: () => void;
  unregister: () => void;
  agentTarget: AgentTarget | null;
  setAgentTarget: (t: AgentTarget | null) => void;
}

const ModalContext = createContext<ModalContextValue | null>(null);

export function ModalProvider({ children }: { children: ReactNode }) {
  const [count, setCount] = useState(0);
  const [agentTarget, setAgentTarget] = useState<AgentTarget | null>(null);

  const register = useCallback(() => setCount((n) => n + 1), []);
  const unregister = useCallback(() => setCount((n) => Math.max(0, n - 1)), []);

  return (
    <ModalContext.Provider value={{ count, register, unregister, agentTarget, setAgentTarget }}>
      {children}
    </ModalContext.Provider>
  );
}

/** Read/set the dock's context-bound Agent target (see AgentTarget). */
export function useAgentTarget(): { agentTarget: AgentTarget | null; setAgentTarget: (t: AgentTarget | null) => void } {
  const ctx = useContext(ModalContext);
  return {
    agentTarget: ctx?.agentTarget ?? null,
    setAgentTarget: ctx?.setAgentTarget ?? (() => {}),
  };
}

/**
 * Call from any full-screen modal: increments on mount, decrements on unmount.
 *
 * OP10: page-like modals (DayDetailSheet) that WANT the dock to stay visible
 * pass `{ keepDock: true }` — they skip registration entirely, so the dock's
 * `useIsAnyModalOpen()` stays false and the dock keeps floating (at z-[60],
 * above the page-modal). Picker/form modals omit the flag → dock hides as
 * before (they're transient overlays where the dock would just clutter).
 */
export function useModalMount(opts?: { keepDock?: boolean }) {
  const ctx = useContext(ModalContext);
  const keepDock = opts?.keepDock ?? false;
  // No-op if no provider (e.g. in unit tests) — fail soft so callers don't crash
  useEffect(() => {
    if (!ctx || keepDock) return;
    ctx.register();
    return () => ctx.unregister();
  }, [ctx, keepDock]);
}

export function useIsAnyModalOpen(): boolean {
  const ctx = useContext(ModalContext);
  return (ctx?.count ?? 0) > 0;
}
