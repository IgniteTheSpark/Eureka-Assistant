"use client";

import { useState, useCallback, useEffect } from "react";
import { api } from "@/lib/api";
import type { Asset } from "@/lib/types";

function todayLocalDateStr() {
  // Returns "YYYY-MM-DD" in LOCAL timezone
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function assetDateStr(created_at: string): string {
  // Parse the ISO string and return local "YYYY-MM-DD"
  try {
    const d = new Date(created_at);
    const y = d.getFullYear();
    const mo = String(d.getMonth() + 1).padStart(2, "0");
    const da = String(d.getDate()).padStart(2, "0");
    return `${y}-${mo}-${da}`;
  } catch {
    return "";
  }
}

export function useStream() {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      // Fetch all recent assets (not just today) — limit 50
      const res = await api.getAssets({ limit: 200 });
      if (res.ok) {
        // Sort newest first, then filter to today on client side for display
        setAssets(res.assets ?? []);
      } else {
        setError(res.error ?? "加载失败");
        setAssets([]);
      }
    } catch (err) {
      setError(String(err));
      setAssets([]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Today's assets: compare local date strings
  const today = todayLocalDateStr();
  const todayAssets = assets.filter((a) => assetDateStr(a.created_at) === today);

  return { assets, todayAssets, isLoading, error, refresh: load };
}
