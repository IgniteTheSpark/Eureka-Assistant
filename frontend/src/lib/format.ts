/**
 * lib/format — value formatters mirroring backend's `_apply_format` in
 * agents/flash_pipeline.py. Used by render-spec interpreter + GenericField.
 *
 * Formats (from Phase B §九.1):
 *   text           — pass-through
 *   relative_date  — "5月22日 15:00" or "5月22日截止" (date-only with deadline suffix)
 *   absolute_date  — same shape but no "截止" suffix (used by expense date)
 *   time           — "15:00"
 *   currency       — "¥85"
 *   duration       — "2小时" / "30分钟"
 *   badge          — pass-through (render hint, frontend styles it)
 *   truncate_30/40/60 — "<n chars>…"
 */

import type { FieldFormat } from "./render-spec";

/**
 * Strict ISO8601 datetime detector. Used both to auto-format a raw value
 * that looks like a timestamp AND to refuse date-formatting a value that
 * obviously isn't one (e.g. a small number the AI mistakenly tagged with
 * `secondary_format: absolute_date`).
 */
const ISO_DT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
function looksLikeIsoTimestamp(v: unknown): v is string {
  if (typeof v !== "string") return false;
  return ISO_DT_RE.test(v) || ISO_DATE_RE.test(v);
}

export function applyFormat(value: unknown, format?: FieldFormat): string {
  if (value === null || value === undefined || value === "") return "";
  const s = String(value);

  // No explicit format directive — but the value LOOKS like an ISO
  // datetime. Auto-format so meta fields don't dump raw ISO on the user
  // (May audit: chat card meta showed "2026-05-30T08:00:00+08:00").
  if (!format) {
    return looksLikeIsoTimestamp(value) ? formatDate(s, { withDeadlineSuffix: false }) : s;
  }

  switch (format) {
    case "relative_date":
      // Defensive: AI sometimes tags a non-date value with a date format
      // (e.g. amount=120 with secondary_format:absolute_date → "1月1日").
      // If the value clearly isn't a date string, fall back to text.
      if (!looksLikeIsoTimestamp(value)) return s;
      return formatDate(s, { withDeadlineSuffix: true });
    case "absolute_date":
      if (!looksLikeIsoTimestamp(value)) return s;
      return formatDate(s, { withDeadlineSuffix: false });
    case "time":
      if (!looksLikeIsoTimestamp(value)) return s;
      return formatTime(s);
    case "currency":
      return `¥${s}`;
    case "duration":
      return formatDuration(s);
    case "badge":
    case "text":
      return s;
    default: {
      // truncate_NN
      if (format.startsWith("truncate_")) {
        const n = Number(format.slice("truncate_".length)) || 40;
        return s.length > n ? `${s.slice(0, n)}…` : s;
      }
      return s;
    }
  }
}

/**
 * Parse ISO8601 datetime and format compactly:
 *   - if it has a time component: "5月22日 15:00"
 *   - if date-only:
 *       withDeadlineSuffix=true  → "5月22日截止" (todo's due_date)
 *       withDeadlineSuffix=false → "5月22日"     (expense date)
 *
 * Tolerates plain "YYYY-MM-DD" and full ISO8601.
 */
function formatDate(
  raw: string,
  { withDeadlineSuffix }: { withDeadlineSuffix: boolean },
): string {
  // Accept "Z" suffix and naive date strings
  const normalized = raw.replace(/Z$/, "+00:00");
  const d = new Date(normalized);
  if (Number.isNaN(d.getTime())) return raw;

  const month = d.getMonth() + 1;
  const day = d.getDate();
  const hours = d.getHours();
  const minutes = d.getMinutes();
  const hasTime = hours !== 0 || minutes !== 0;

  if (hasTime) {
    const hh = String(hours).padStart(2, "0");
    const mm = String(minutes).padStart(2, "0");
    return `${month}月${day}日 ${hh}:${mm}`;
  }
  return withDeadlineSuffix ? `${month}月${day}日截止` : `${month}月${day}日`;
}

function formatTime(raw: string): string {
  const d = new Date(raw.replace(/Z$/, "+00:00"));
  if (Number.isNaN(d.getTime())) return raw;
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

/**
 * Accept "2h" / "30m" / "2:30" / a plain number of minutes.
 * Returns "2 小时" / "30 分钟" / "2 小时 30 分钟".
 */
function formatDuration(raw: string): string {
  // Plain number → minutes
  const asNum = Number(raw);
  if (!Number.isNaN(asNum)) {
    return minutesToText(asNum);
  }
  // "2h" / "30m" / "1h30m"
  const m = raw.match(/^(?:(\d+)h)?(?:(\d+)m)?$/);
  if (m) {
    const h = Number(m[1] ?? 0);
    const min = Number(m[2] ?? 0);
    return minutesToText(h * 60 + min);
  }
  return raw;
}

function minutesToText(total: number): string {
  if (total <= 0) return "0 分钟";
  const h = Math.floor(total / 60);
  const m = total % 60;
  if (h === 0) return `${m} 分钟`;
  if (m === 0) return `${h} 小时`;
  return `${h} 小时 ${m} 分钟`;
}
