export interface Card {
  type: string;
  title?: string;
  subtitle?: string;
  /** Asset UUID — present when the card represents a DB asset (created via MCP).
   *  Used by AgentChatPage to navigate directly to AssetDetailPage. */
  asset_id?: string;
  /** Session UUID — present when the card represents or is sourced from a session. */
  session_id?: string;
}

export interface Session {
  id: string;
  session_type: string;
  title?: string;
  date?: string;
  created_at: string;
}

/** Raw asset from the DB — payload shape depends on asset_type */
export interface Asset {
  id: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  payload: Record<string, any>;
  session_id?: string;
  created_at: string;
}

export interface SessionsResponse {
  ok: boolean;
  sessions: Session[];
  error?: string;
}

export interface AssetsResponse {
  ok: boolean;
  assets: Asset[];
  error?: string;
}

export interface QueryResponse {
  ok: boolean;
  answer?: string;
  cards?: Card[];
  summary?: string;
  session_id?: string;
  elapsed_ms?: number;
  input_tokens?: number;
  output_tokens?: number;
  error?: string;
}

export interface FlashResponse {
  ok: boolean;
  session_id: string;
  summary?: string;
  cards?: Card[];
  has_pending?: boolean;
  elapsed_ms?: number;
  error?: string;
}

export interface FlashAudioResponse {
  ok: boolean;
  session_id: string;
  summary?: string;
  cards?: Card[];
  has_pending?: boolean;
  transcript: string;
  audio_url: string;
  error?: string;
}

export type StreamView = "timeline" | "workspace";

export type PageId =
  | "p-stream"
  | "p-agent-chat"
  | "p-day-view"
  | "p-flash-sess"
  | "p-flash-overall"
  | "p-workspace"
  | "p-asset-detail";

export interface ContactItem {
  id: string;
  name: string;
  phone?: string | null;
  company?: string | null;
  title?: string | null;
  email?: string | null;
  notes?: string[];
  created_at: string;
}

export interface ContactsResponse {
  ok: boolean;
  contacts: ContactItem[];
  error?: string;
}

export interface ChatMessage {
  id: string;
  role: "user" | "agent";
  text: string;
  cards?: Card[];
  elapsed_ms?: number;
  input_tokens?: number;
  output_tokens?: number;
  error?: boolean;
}
