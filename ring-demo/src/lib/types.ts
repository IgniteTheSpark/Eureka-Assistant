export type DemoMode = "idle" | "flash" | "vibe";

export type RingStatus = "loading" | "ready" | "error";

export interface User {
  id: string;
  email: string;
}

export interface AuthResponse {
  ok: boolean;
  token: string;
  user: User;
}

export interface MeResponse {
  ok: boolean;
  user: User;
}

export interface FlashResponse {
  ok: boolean;
  session_id?: string;
  input_turn_id?: string;
  reply?: string;
  summary?: string;
  cards: Array<Record<string, unknown>>;
  derived_assets?: Array<Record<string, unknown>>;
  has_pending?: boolean;
  elapsed_ms?: number;
}

export interface RingDevice {
  address: string;
  name: string;
  rssi?: number;
}

export interface RingConnectionSnapshot {
  status: string;
  connected: boolean;
  device: RingDevice | null;
  devices: RingDevice[];
  lastError: string | null;
}

export type RingMapping = Record<string, string> | null;

export interface DemoSnapshot {
  sessionId: string | null;
  mode: DemoMode;
  generation: number;
  leaseExpiresAt?: number | null;
  connection: RingConnectionSnapshot;
  activeApp?: string | null;
  mapping?: RingMapping;
}

export interface RingEvent {
  event: string;
  data: Record<string, unknown>;
}
