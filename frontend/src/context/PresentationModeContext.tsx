import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";

/**
 * PresentationMode — per Phase A §七 / Phase B decision #7.
 *
 * Two presets for the same five pages:
 *   - "asset"    — knowledge-precipitation people; Library is the home
 *   - "calendar" — business / boss people; Calendar is the home
 *
 * The five pages and the navigation don't change; only the default home does.
 * Stored in localStorage; on auth, swap implementation behind this hook
 * without touching call sites.
 */

export type PresentationMode = "asset" | "calendar";

interface PresentationModeContextValue {
  mode: PresentationMode;
  setMode: (mode: PresentationMode) => void;
  /** Default landing route per current mode — used by the index redirect. */
  homeRoute: string;
}

const STORAGE_KEY = "eureka:presentation_mode";

const PresentationModeContext = createContext<PresentationModeContextValue | null>(null);

export function PresentationModeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<PresentationMode>(() => {
    if (typeof window === "undefined") return "asset";
    const stored = window.localStorage.getItem(STORAGE_KEY);
    return stored === "calendar" || stored === "asset" ? stored : "asset";
  });

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, mode);
  }, [mode]);

  const setMode = useCallback((next: PresentationMode) => {
    setModeState(next);
  }, []);

  const value = useMemo<PresentationModeContextValue>(
    () => ({
      mode,
      setMode,
      homeRoute: mode === "calendar" ? "/calendar" : "/library",
    }),
    [mode, setMode],
  );

  return (
    <PresentationModeContext.Provider value={value}>{children}</PresentationModeContext.Provider>
  );
}

export function usePresentationMode(): PresentationModeContextValue {
  const ctx = useContext(PresentationModeContext);
  if (!ctx) {
    throw new Error("usePresentationMode must be used inside <PresentationModeProvider>");
  }
  return ctx;
}
