"use client";

import React, {
  createContext,
  useContext,
  useState,
  useCallback,
  useRef,
  type ReactNode,
} from "react";
import type { PageId } from "@/lib/types";

export type NavParams = Record<string, string>;

interface PageEntry {
  id: PageId;
  params: NavParams;
}

interface NavContextValue {
  currentPage: PageId;
  currentParams: NavParams;
  pageStack: PageEntry[];
  navTo: (id: PageId, params?: NavParams) => void;
  goBack: () => void;
  /** How many times this page has been the top of the stack.
   *  Pages use this as a useEffect dependency to refetch when re-visited. */
  usePageVisitCount: (pageId: PageId) => number;
}

const NavContext = createContext<NavContextValue | null>(null);

export function NavProvider({ children }: { children: ReactNode }) {
  const [pageStack, setPageStack] = useState<PageEntry[]>([
    { id: "p-stream", params: {} },
  ]);
  // Track visit counts per page so components can re-fetch when re-activated.
  const visitCountsRef = useRef<Partial<Record<PageId, number>>>({});
  const [visitCounts, setVisitCounts] = useState<Partial<Record<PageId, number>>>({});

  const navTo = useCallback((id: PageId, params: NavParams = {}) => {
    setPageStack((prev) => [...prev, { id, params }]);
    visitCountsRef.current[id] = (visitCountsRef.current[id] ?? 0) + 1;
    setVisitCounts({ ...visitCountsRef.current });
  }, []);

  const goBack = useCallback(() => {
    setPageStack((prev) => {
      if (prev.length <= 1) return prev;
      const next = prev.slice(0, -1);
      const revealedId = next[next.length - 1].id;
      visitCountsRef.current[revealedId] = (visitCountsRef.current[revealedId] ?? 0) + 1;
      setVisitCounts({ ...visitCountsRef.current });
      return next;
    });
  }, []);

  const usePageVisitCount = useCallback((pageId: PageId) => {
    return visitCounts[pageId] ?? 0;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visitCounts]);

  const currentEntry = pageStack[pageStack.length - 1];

  return (
    <NavContext.Provider
      value={{
        currentPage: currentEntry.id,
        currentParams: currentEntry.params,
        pageStack,
        navTo,
        goBack,
        usePageVisitCount,
      }}
    >
      {children}
    </NavContext.Provider>
  );
}

export function useNav(): NavContextValue {
  const ctx = useContext(NavContext);
  if (!ctx) throw new Error("useNav must be used inside NavProvider");
  return ctx;
}
