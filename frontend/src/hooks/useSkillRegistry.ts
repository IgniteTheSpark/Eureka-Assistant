import useSWR from "swr";

import { apiFetch, swrFetcher } from "@/lib/api";
import type { Skill, SkillsResponse } from "@/lib/types";

/**
 * Persist a drag-to-reorder of the SKILLS grid.
 * `orderedIds` is the full list of user_skill_ids top-left to bottom-right.
 * Backend rewrites positions 0..N-1 in one transaction.
 */
export async function reorderSkills(orderedIds: string[]): Promise<void> {
  const resp = await apiFetch<{ ok: boolean; count?: number; error?: string }>(
    "/api/skills/reorder",
    { method: "PUT", body: { order: orderedIds } },
  );
  if (!resp.ok) throw new Error(resp.error ?? "reorder failed");
}

/**
 * useSkillRegistry — fetch all UserSkills + their render_spec.
 *
 * Skills change rarely (only when user adds a new one via AddSkillWizard),
 * so we let SWR cache aggressively. Use `revalidateOnFocus: false` to avoid
 * thrash when user comes back to tab.
 *
 * Returns:
 *   skills    — full list, ordered as backend returns
 *   bySkill   — keyed by machine name for quick lookup in SkillCard
 *   isLoading
 *   error
 */
export function useSkillRegistry() {
  const { data, error, isLoading, mutate } = useSWR<SkillsResponse>(
    "/api/skills",
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const skills = data?.skills ?? [];
  const bySkill = new Map<string, Skill>(skills.map((s) => [s.name, s]));

  return {
    skills,
    bySkill,
    isLoading,
    error,
    refresh: mutate,
  };
}
