/**
 * lib/types — API response shapes returned by the Eureka backend.
 * Kept narrow — only the fields the frontend currently consumes. Extend as needed.
 */

import type { RenderSpec } from "./render-spec";

/* ── /api/skills ─────────────────────────────────────────────────────────── */

export interface Skill {
  user_skill_id: string;
  name: string;           // machine name: "todo" | "idea" | ...
  display_name: string;   // localized: "待办" | "想法" | ...
  payload_schema: Record<string, unknown> | null;
  render_spec: RenderSpec | null;
  queryable_fields: Array<{ field: string; index_type: string }> | null;
  /** 0-based slot in the library's 3x3 SKILLS grid. */
  position?: number;
}

export interface SkillsResponse {
  ok: boolean;
  skills: Skill[];
}

/* ── /api/assets ─────────────────────────────────────────────────────────── */

export interface Asset {
  id: string;
  user_skill_name: string;
  payload: Record<string, unknown>;
  session_id: string | null;
  source_input_turn_id: string | null;
  created_at: string;
}

export interface AssetsResponse {
  ok: boolean;
  assets: Asset[];
}

/* ── /api/events ─────────────────────────────────────────────────────────── */

// Note: /api/events response uses `event_id` (NOT `id`) — matches the MCP
// server's list_events tool output. Don't rename to `id`; the backend is the
// single source of truth and we follow.
export interface Event {
  event_id: string;
  title: string;
  start_at: string;
  end_at: string | null;
  all_day: boolean;
  location: string | null;
  description: string | null;
  recurrence_rule: string | null;
  status: string;
  source_input_turn_id: string | null;
  created_at: string;
  updated_at?: string;
  attendees?: Array<{
    attendee_id: string;
    contact_id: string | null;
    name: string;
    role: string;
  }>;
  files?: unknown[];
}

export interface EventsResponse {
  ok: boolean;
  events: Event[];
}

/* ── /api/timeline ──────────────────────────────────────────────────────── */

/**
 * TimelineItem — uniform record across asset / event so the timeline view can
 * group + sort by effective_at. Backend returns both kinds in one array
 * (sorted descending by effective_at).
 *
 * `kind: "event"` items carry event-specific fields (end_at, location, all_day,
 * event_id). `kind: "asset"` items carry asset fields (skill_name, payload,
 * session_id). Use kind to discriminate.
 */
export interface TimelineItem {
  kind: "event" | "asset";
  id: string;
  effective_at: string;
  created_at: string;
  title: string;
  subtitle?: string;
  source_input_turn_id: string | null;

  // event-only
  event_id?: string;
  end_at?: string | null;
  location?: string | null;
  all_day?: boolean;

  // asset-only
  skill_name?: string;
  session_id?: string | null;
  payload?: Record<string, unknown>;
}

export interface TimelineResponse {
  ok: boolean;
  items: TimelineItem[];
}

/* ── /api/files ─────────────────────────────────────────────────────────── */

export interface FileRow {
  id: string;
  file_type: string | null;
  source_tag: string | null;
  duration_sec: number | null;
  asr_status: string | null;
  asr_text: string | null;
  turn_count: number;
  asset_count: number;
  created_at: string;
}

export interface FilesResponse {
  ok: boolean;
  files: FileRow[];
}

/* ── /api/contacts ──────────────────────────────────────────────────────── */

export interface Contact {
  id: string;
  name: string;
  phone: string | null;
  company: string | null;
  title: string | null;
  email: string | null;
  notes: string[];
  created_at: string;
}

export interface ContactsResponse {
  ok: boolean;
  contacts: Contact[];
}

/* ── /api/sessions ──────────────────────────────────────────────────────── */

export interface Session {
  id: string;
  session_type: "flash" | "chat" | "meeting" | "manual";
  title: string | null;
  date: string | null;
  created_at: string;
  /** M2.2: asset ids the user explicitly attached as session context */
  context_asset_ids?: string[];
}

export interface SessionDetail {
  id: string;
  session_type: "flash" | "chat" | "meeting" | "manual";
  title: string | null;
  date: string | null;
  created_at: string;
  context_asset_ids: string[];
  // M2.3 subject FKs — exactly one is non-null for home discussion sessions
  event_id:         string | null;
  contact_id:       string | null;
  file_id:          string | null;
  subject_asset_id: string | null;
  asset_count: number;
  turn_count: number;
  assets: Array<{ id: string; payload: Record<string, unknown>; created_at: string }>;
}

export interface SessionDetailResponse {
  ok: boolean;
  session: SessionDetail;
}

export interface CreateSessionResponse {
  ok: boolean;
  session_id: string;
  context_asset_ids?: string[];
}

export interface SessionsResponse {
  ok: boolean;
  sessions: Session[];
}

/* ── /api/sessions/:id/messages ─────────────────────────────────────────── */

export interface Message {
  id: string;
  role: "user" | "agent" | "tool";
  text: string;
  tool_call: { name: string; args: Record<string, unknown> } | null;
  tool_result: { name: string; response: Record<string, unknown> } | null;
  cards: Array<Record<string, unknown>>;
  elapsed_ms: number | null;
  created_at: string;
}

export interface MessagesResponse {
  ok: boolean;
  messages: Message[];
}

/* ── /api/notifications ─────────────────────────────────────────────────── */

export type NotificationType =
  | "flash_done"
  | "task_done"
  | "task_failed"
  | "reminder";

export interface Notification {
  id: string;
  type: NotificationType | string;
  title: string;
  body: string;
  /** opaque deep-link target the frontend resolves (asset/event id) */
  link: string | null;
  read: boolean;
  created_at: string | null;
}

export interface NotificationsResponse {
  ok: boolean;
  notifications: Notification[];
  unread: number;
}

/* ── /api/tasks ─────────────────────────────────────────────────────────── */

export interface Task {
  id: string;
  user_text: string;
  mcp_target: string | null;
  status: "pending" | "running" | "done" | "failed";
  error_message: string | null;
  result_asset_id: string | null;
  result_asset_payload: Record<string, unknown> | null;
  session_id: string | null;
  source_input_turn_id: string | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
}

export interface TasksResponse {
  ok: boolean;
  tasks: Task[];
}
