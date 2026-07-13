import type { QueryResponse, FlashResponse, FlashAudioResponse, SessionsResponse, AssetsResponse, ContactsResponse } from "./types";

// In dev, Next.js rewrites /api/* → http://localhost:8000/api/*
// so we use relative paths in both dev and prod.
const BASE = "";

export const api = {
  async getSessionMessages(session_id: string): Promise<{
    ok: boolean;
    messages: { id: string; role: "user" | "agent"; text: string; cards: unknown[]; elapsed_ms?: number; created_at: string }[];
    error?: string;
  }> {
    try {
      const res = await fetch(`${BASE}/api/sessions/${session_id}/messages`);
      if (!res.ok) return { ok: false, messages: [], error: `HTTP ${res.status}` };
      return res.json();
    } catch (err) {
      return { ok: false, messages: [], error: String(err) };
    }
  },

  async askAgent(
    question: string,
    session_id?: string,
    history?: { role: "user" | "agent"; text: string }[],
  ): Promise<QueryResponse> {
    try {
      const res = await fetch(`${BASE}/api/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, session_id: session_id ?? "", history: history ?? [] }),
      });
      if (!res.ok) {
        const text = await res.text();
        return { ok: false, error: `HTTP ${res.status}: ${text}` };
      }
      return res.json();
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  },

  async getSessions(opts?: { date?: string; session_type?: string }): Promise<SessionsResponse> {
    try {
      const p = new URLSearchParams();
      if (opts?.date) p.set("date", opts.date);
      if (opts?.session_type) p.set("session_type", opts.session_type);
      const params = p.toString() ? `?${p.toString()}` : "";
      const res = await fetch(`${BASE}/api/sessions${params}`);
      if (!res.ok) return { ok: false, sessions: [], error: `HTTP ${res.status}` };
      return res.json();
    } catch (err) {
      return { ok: false, sessions: [], error: String(err) };
    }
  },

  async getAssets(opts?: { type?: string; session_id?: string; contains?: string; limit?: number }): Promise<AssetsResponse> {
    try {
      const p = new URLSearchParams();
      if (opts?.type) p.set("type", opts.type);
      if (opts?.session_id) p.set("session_id", opts.session_id);
      if (opts?.contains) p.set("contains", opts.contains);
      if (opts?.limit) p.set("limit", String(opts.limit));
      const qs = p.toString();
      const res = await fetch(`${BASE}/api/assets${qs ? `?${qs}` : ""}`);
      if (!res.ok) return { ok: false, assets: [], error: `HTTP ${res.status}` };
      const data = await res.json();
      // Normalize: MCP fallback returns {asset_id, asset_type, ...} while structured query returns {id, ...}
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const normalized = (data.assets ?? []).map((a: any) => ({
        id: a.id ?? a.asset_id ?? "",
        payload: { ...a.payload, asset_type: a.asset_type ?? a.payload?.asset_type },
        session_id: a.session_id,
        created_at: a.created_at ?? "",
      }));
      return { ok: data.ok, assets: normalized, error: data.error };
    } catch (err) {
      return { ok: false, assets: [], error: String(err) };
    }
  },

  async flashAudio(file: File, session_id?: string): Promise<FlashAudioResponse> {
    try {
      const form = new FormData();
      form.append("audio", file);
      if (session_id) form.append("session_id", session_id);
      const res = await fetch(`${BASE}/api/flash/audio`, {
        method: "POST",
        body: form,
      });
      if (!res.ok) {
        const errText = await res.text();
        return { ok: false, session_id: "", transcript: "", audio_url: "", error: `HTTP ${res.status}: ${errText}` };
      }
      return res.json();
    } catch (err) {
      return { ok: false, session_id: "", transcript: "", audio_url: "", error: String(err) };
    }
  },

  async getContacts(opts?: { q?: string; limit?: number }): Promise<ContactsResponse> {
    try {
      const p = new URLSearchParams();
      if (opts?.q) p.set("q", opts.q);
      if (opts?.limit) p.set("limit", String(opts.limit));
      const qs = p.toString();
      const res = await fetch(`${BASE}/api/contacts${qs ? `?${qs}` : ""}`);
      if (!res.ok) return { ok: false, contacts: [], error: `HTTP ${res.status}` };
      return res.json();
    } catch (err) {
      return { ok: false, contacts: [], error: String(err) };
    }
  },

  async getSession(id: string): Promise<{ ok: boolean; session?: { id: string; session_type: string; title: string | null; date: string | null; created_at: string }; error?: string }> {
    try {
      const res = await fetch(`${BASE}/api/sessions/${id}`);
      if (!res.ok) return { ok: false, error: `HTTP ${res.status}` };
      return res.json();
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  },

  async getAsset(id: string): Promise<{ ok: boolean; asset?: import("./types").Asset; error?: string }> {
    try {
      const res = await fetch(`${BASE}/api/assets/${id}`);
      if (!res.ok) return { ok: false, error: `HTTP ${res.status}` };
      const data = await res.json();
      return data;
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  },

  async updateAsset(
    id: string,
    payloadPatch: Record<string, unknown>
  ): Promise<{ ok: boolean; asset?: import("./types").Asset; error?: string }> {
    try {
      const res = await fetch(`${BASE}/api/assets/${id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ payload_patch: payloadPatch }),
      });
      if (!res.ok) {
        const text = await res.text();
        return { ok: false, error: `HTTP ${res.status}: ${text}` };
      }
      return res.json();
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  },

  async flash(text: string, session_id?: string, is_followup?: boolean, is_voice?: boolean): Promise<FlashResponse> {
    try {
      const res = await fetch(`${BASE}/api/flash`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, session_id, is_followup: is_followup ?? false, is_voice: is_voice ?? false }),
      });
      if (!res.ok) {
        const errText = await res.text();
        return { ok: false, session_id: "", error: `HTTP ${res.status}: ${errText}` };
      }
      return res.json();
    } catch (err) {
      return { ok: false, session_id: "", error: String(err) };
    }
  },
};
