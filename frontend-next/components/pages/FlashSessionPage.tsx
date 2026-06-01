"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { useNav } from "@/context/NavContext";
import { api } from "@/lib/api";
import type { Asset, Session } from "@/lib/types";

// ── Helpers ───────────────────────────────────────────────────────────────────

function todayLocalDateStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
}

function assetDateStr(iso: string) {
  try {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
  } catch { return ""; }
}

// ── Message types ─────────────────────────────────────────────────────────────

// card_type (new pipeline) or type (legacy) both accepted
interface FlashCard { type?: string; card_type?: string; title: string; subtitle?: string; }

interface FlashMessage {
  id: string;
  role: "user" | "agent";
  text: string;
  cards?: FlashCard[];
  elapsed_ms?: number;
  isLoading?: boolean;
  isError?: boolean;
}

// Derive card title / subtitle from a raw Asset (for history reconstruction)
const TYPE_ICON: Record<string, string> = {
  todo: "✅", expense: "💰", contact: "👤", idea: "💡", note: "📄", transcript: "🎙",
};

function formatDueShort(raw: unknown): string {
  if (!raw) return "";
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return s.slice(0, 16);
  const month = Number(m[2]);
  const day   = Number(m[3]);
  const tm = s.match(/T(\d{2}):(\d{2})/);
  if (tm && !(tm[1] === "00" && tm[2] === "00")) {
    return `${month}月${day}日 ${tm[1]}:${tm[2]}`;
  }
  return `${month}月${day}日截止`;
}

function assetToCard(a: Asset): FlashCard {
  const p = a.payload;
  const t = (p.asset_type as string) ?? "misc";
  let title = "";
  let subtitle = "";
  if (t === "todo")    { title = (p.content ?? p.title ?? "待办") as string; subtitle = formatDueShort(p.due_date); }
  else if (t === "expense") { title = `¥${p.amount ?? ""} ${p.description ?? p.merchant ?? "消费"}`; subtitle = (p.category ?? "") as string; }
  else if (t === "contact") { title = (p.name ?? "联系人") as string; subtitle = [p.company, p.phone].filter(Boolean).join(" · "); }
  else { title = (p.title ?? p.content ?? t) as string; }
  return { type: t, title: title.slice(0, 40), subtitle: subtitle.slice(0, 30) };
}

// ── Card chip (inside agent bubble) ──────────────────────────────────────────

function CardChip({ card }: { card: FlashCard }) {
  const cardType = card.card_type ?? card.type ?? "note";
  const icon = TYPE_ICON[cardType] ?? "📎";
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: "8px",
      padding: "8px 10px",
      background: "var(--surface2)", border: "1px solid var(--border)",
      borderRadius: "var(--rs)",
    }}>
      <span style={{ fontSize: "14px", flexShrink: 0 }}>{icon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: "12px", fontWeight: 600, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
          {card.title}
        </div>
        {card.subtitle && (
          <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
            {card.subtitle}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Message bubble ────────────────────────────────────────────────────────────

function MessageBubble({ msg }: { msg: FlashMessage }) {
  if (msg.role === "user") {
    return (
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <div style={{
          maxWidth: "78%", padding: "10px 14px",
          background: "var(--grad)", color: "#fff",
          borderRadius: "18px 18px 4px 18px",
          fontSize: "13px", lineHeight: 1.6,
          boxShadow: "0 2px 10px rgba(59,91,245,.25)",
        }}>
          {msg.text}
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", alignItems: "flex-start", gap: "8px" }}>
      {/* Avatar */}
      <div style={{
        width: "30px", height: "30px", borderRadius: "50%", flexShrink: 0,
        background: "var(--grad)", display: "grid", placeItems: "center",
        fontSize: "13px", color: "#fff", marginTop: "2px",
        boxShadow: "0 2px 8px rgba(59,91,245,.3)",
      }}>✦</div>

      <div style={{ flex: 1, minWidth: 0 }}>
        {/* Text bubble */}
        <div style={{
          background: msg.isError ? "rgba(220,38,38,.06)" : "var(--surface)",
          border: `1px solid ${msg.isError ? "rgba(220,38,38,.2)" : "var(--border)"}`,
          borderRadius: "4px 18px 18px 18px",
          padding: "10px 14px",
          boxShadow: "var(--sh-s)",
        }}>
          {msg.isLoading ? (
            <span style={{ color: "var(--text3)", fontStyle: "italic", fontSize: "13px" }}>
              处理中…
            </span>
          ) : (
            <span style={{
              fontSize: "13px",
              color: msg.isError ? "var(--red)" : "var(--text)",
              lineHeight: 1.65,
              whiteSpace: "pre-wrap",
            }}>
              {msg.text || (msg.cards && msg.cards.length > 0 ? "" : "（无回复）")}
            </span>
          )}
        </div>

        {/* Extracted asset cards — skip qa cards (answer already shown as text) */}
        {!msg.isLoading && msg.cards && msg.cards.filter(c => (c.card_type ?? c.type) !== "qa").length > 0 && (
          <div style={{ marginTop: "6px", display: "flex", flexDirection: "column", gap: "4px" }}>
            {msg.cards
              .filter(c => (c.card_type ?? c.type) !== "qa")
              .map((card, i) => <CardChip key={i} card={card} />)}
          </div>
        )}

        {/* Elapsed time metadata */}
        {!msg.isLoading && !msg.isError && msg.elapsed_ms !== undefined && msg.elapsed_ms > 0 && (
          <div style={{ marginTop: "4px", fontSize: "9px", color: "var(--text3)", paddingLeft: "2px" }}>
            {(msg.elapsed_ms / 1000).toFixed(1)}s
          </div>
        )}
      </div>
    </div>
  );
}

// ── Session drawer (side panel — same pattern as AgentChatPage) ───────────────

function SessionDrawer({
  sessions, activeId, onPick, onClose,
}: {
  sessions: Session[]; activeId: string;
  onPick: (s: Session) => void; onClose: () => void;
}) {
  return (
    <>
      {/* Backdrop */}
      <div onClick={onClose} style={{
        position: "absolute", inset: 0, zIndex: 40,
        background: "rgba(10,14,30,.4)", backdropFilter: "blur(2px)",
      }} />
      {/* Side panel */}
      <div style={{
        position: "absolute",
        top: 0, right: 0, bottom: 0,
        width: "78%",
        background: "var(--surface)",
        zIndex: 50,
        display: "flex", flexDirection: "column",
        boxShadow: "-4px 0 20px rgba(15,23,42,.18)",
      }} onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div style={{
          padding: "14px 14px 10px",
          borderBottom: "1px solid var(--border)",
          display: "flex", alignItems: "center", gap: "8px", flexShrink: 0,
        }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>对话记录</div>
            <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
              共 {sessions.length} 次对话
            </div>
          </div>
          <button onClick={onClose} style={{
            width: "28px", height: "28px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "16px", color: "var(--text3)", cursor: "pointer",
          }}>×</button>
        </div>

        {/* Session list */}
        <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "10px 12px 16px" }}>
          {sessions.length === 0 && (
            <div style={{ textAlign: "center", color: "var(--text3)", fontSize: "12px", marginTop: "32px" }}>
              暂无历史记录
            </div>
          )}
          <div style={{ display: "flex", flexDirection: "column", gap: "6px", marginTop: "4px" }}>
            {sessions.map((s) => {
              const active = s.id === activeId;
              const icon = s.session_type === "daily" ? "⚡" : s.session_type === "agent_chat" ? "✦" : "🎙";
              const iconColor = s.session_type === "daily" ? "var(--amber)" : "var(--blue)";
              return (
                <div key={s.id} onClick={() => onPick(s)} style={{
                  display: "flex", alignItems: "center", gap: "10px",
                  padding: "10px 12px",
                  background: active ? "color-mix(in srgb, var(--blue) 6%, transparent)" : "var(--surface2)",
                  border: `1px solid ${active ? "color-mix(in srgb, var(--blue) 20%, transparent)" : "var(--border)"}`,
                  borderRadius: "var(--rs)",
                  cursor: "pointer",
                }}>
                  <div style={{
                    width: "28px", height: "28px", borderRadius: "8px", flexShrink: 0,
                    background: `color-mix(in srgb, ${iconColor} 12%, transparent)`,
                    border: `1px solid color-mix(in srgb, ${iconColor} 22%, transparent)`,
                    display: "grid", placeItems: "center", fontSize: "13px",
                  }}>{icon}</div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{
                      fontSize: "12px", fontWeight: 600,
                      color: active ? "var(--blue)" : "var(--text)",
                      overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
                    }}>{s.title ?? "Session"}</div>
                    <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
                      {s.date ?? ""}
                    </div>
                  </div>
                  {active
                    ? <span style={{ fontSize: "9px", fontWeight: 700, color: "var(--blue)", flexShrink: 0 }}>当前</span>
                    : <span style={{ fontSize: "14px", color: "var(--text3)", flexShrink: 0 }}>›</span>}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

let _msgId = 0;
function newId() { return `fmsg-${++_msgId}-${Date.now()}`; }

export default function FlashSessionPage() {
  const { goBack, navTo, currentParams, usePageVisitCount } = useNav();
  const targetSessionId = currentParams.session_id ?? "";

  const [messages, setMessages] = useState<FlashMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError]   = useState<string | null>(null);

  const [pickerOpen, setPickerOpen]   = useState(false);
  const [allSessions, setAllSessions] = useState<Session[]>([]);

  const [input, setInput]       = useState("");
  const [sending, setSending]   = useState(false);

  const scrollRef = useRef<HTMLDivElement>(null);

  function scrollToBottom(immediate = false) {
    const ms = immediate ? 0 : 60;
    setTimeout(() => {
      const el = scrollRef.current;
      if (el) el.scrollTop = el.scrollHeight;
    }, ms);
  }

  // Load session history and reconstruct as chat messages.
  // Two streams are merged by timestamp:
  //   1. Voice flash turns  → reconstructed from flash assets + derived assets
  //   2. Typed follow-up turns → loaded from the messages DB table
  const load = useCallback(async () => {
    setIsLoading(true); setError(null);
    try {
      type DBMsg = { id: string; role: "user" | "agent"; text: string; cards: FlashCard[]; elapsed_ms?: number; created_at: string };
      let assetsToProcess: Asset[] = [];
      let dbMessages: DBMsg[] = [];

      if (targetSessionId) {
        const [assetsRes, msgsRes] = await Promise.all([
          api.getAssets({ session_id: targetSessionId, limit: 200 }),
          api.getSessionMessages(targetSessionId),
        ]);
        if (!assetsRes.ok) { setError(assetsRes.error ?? "加载失败"); return; }
        assetsToProcess = assetsRes.assets ?? [];
        if (msgsRes.ok) dbMessages = msgsRes.messages as DBMsg[];
      } else {
        const res = await api.getAssets({ limit: 200 });
        if (!res.ok) { setError(res.error ?? "加载失败"); return; }
        const today = todayLocalDateStr();
        assetsToProcess = (res.assets ?? []).filter((a) => assetDateStr(a.created_at) === today);
        // No messages merge for "today" fallback view — session_id is required
      }

      // ── 1. Build voice flash turn bubbles ──────────────────────────────────
      const flashAssets = assetsToProcess
        .filter((a) => a.payload.asset_type === "flash")
        .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

      const derivedAssets = assetsToProcess.filter((a) => a.payload.asset_type !== "flash");
      const byInputId = new Map<string, Asset[]>();
      for (const d of derivedAssets) {
        const iid = d.payload.input_id as string | undefined;
        if (iid) { const l = byInputId.get(iid) ?? []; l.push(d); byInputId.set(iid, l); }
      }

      interface BubbleGroup { sortMs: number; bubbles: FlashMessage[] }
      const groups: BubbleGroup[] = [];

      for (const flash of flashAssets) {
        const sortMs = new Date(flash.created_at).getTime();
        const content = (flash.payload.content ?? flash.payload.transcript ?? "") as string;
        const iid = flash.payload.input_id as string | undefined;
        const linked = (iid ? byInputId.get(iid) : undefined) ?? [];
        const agentText = (flash.payload.agent_summary as string | undefined) ?? "";
        const cards = linked.map(assetToCard);

        const pair: FlashMessage[] = [{ id: `u-${flash.id}`, role: "user", text: content }];
        if (agentText || cards.length > 0) {
          pair.push({ id: `a-${flash.id}`, role: "agent", text: agentText, cards });
        }
        groups.push({ sortMs, bubbles: pair });
      }

      // ── 2. Build typed turn bubbles from messages table ────────────────────
      // Messages arrive oldest-first from the backend; pair consecutive user+agent.
      let i = 0;
      while (i < dbMessages.length) {
        const m = dbMessages[i];
        if (m.role !== "user") { i++; continue; }

        const sortMs = new Date(m.created_at).getTime();
        const pair: FlashMessage[] = [{
          id: `msg-u-${m.id}`, role: "user", text: m.text,
        }];

        if (i + 1 < dbMessages.length && dbMessages[i + 1].role === "agent") {
          const ag = dbMessages[i + 1];
          pair.push({
            id: `msg-a-${ag.id}`, role: "agent",
            text: ag.text, cards: ag.cards ?? [], elapsed_ms: ag.elapsed_ms,
          });
          i += 2;
        } else {
          i++;
        }
        groups.push({ sortMs, bubbles: pair });
      }

      // ── 3. Merge and sort by timestamp ─────────────────────────────────────
      groups.sort((a, b) => a.sortMs - b.sortMs);
      setMessages(groups.flatMap(g => g.bubbles));
      scrollToBottom();
    } catch (e) { setError(String(e)); }
    finally { setIsLoading(false); }
  }, [targetSessionId]);

  const visitCount = usePageVisitCount("p-flash-sess");
  useEffect(() => { load(); }, [load, visitCount]);

  useEffect(() => {
    api.getSessions().then((res) => {
      if (res.ok) setAllSessions(res.sessions ?? []);
    });
  }, []);

  async function send() {
    const text = input.trim();
    if (!text || sending) return;
    setSending(true);
    setInput("");

    const userMsgId  = newId();
    const agentMsgId = newId();

    // Snapshot history before adding the new message (last 10 messages = 5 turns)
    const history = messages.slice(-10).map((m) => ({
      role: m.role as "user" | "agent",
      text: m.text,
    }));

    // Optimistic: show user bubble + loading agent bubble
    setMessages(prev => [
      ...prev,
      { id: userMsgId,  role: "user",  text },
      { id: agentMsgId, role: "agent", text: "", isLoading: true },
    ]);
    scrollToBottom();

    try {
      // Typed follow-ups go to /api/query (supports both capture and Q&A via keyword routing),
      // carrying conversation history for multi-turn context.
      // Only voice/audio flash notes go through the flash pipeline.
      const res = await api.askAgent(text, targetSessionId || undefined, history);
      const cards: FlashCard[] = (res.cards ?? []).map((c: { type?: string; card_type?: string; title?: string; subtitle?: string; asset_id?: string }) => ({
        type: c.type ?? c.card_type ?? "note",
        card_type: c.card_type ?? c.type ?? "note",
        title: c.title ?? "",
        subtitle: c.subtitle ?? "",
        asset_id: c.asset_id,
      }));
      const agentText = res.ok
        ? (res.answer || res.summary || (cards.length > 0 ? `已识别 ${cards.length} 项内容` : "好的，已记录"))
        : `❌ ${res.error}`;
      setMessages(prev => prev.map(m =>
        m.id === agentMsgId
          ? { id: agentMsgId, role: "agent", text: agentText, cards: res.ok ? cards : undefined, elapsed_ms: res.elapsed_ms, isError: !res.ok }
          : m
      ));
    } catch (err) {
      setMessages(prev => prev.map(m =>
        m.id === agentMsgId
          ? { id: agentMsgId, role: "agent", text: `网络错误: ${String(err)}`, isError: true }
          : m
      ));
    } finally {
      setSending(false);
      scrollToBottom();
    }
  }

  const activeSession = allSessions.find((s) => s.id === targetSessionId);
  const sessionTitle  = activeSession?.title ?? "今日闪念";

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, background: "var(--bg)", position: "relative" }}>

      {/* Session drawer */}
      {pickerOpen && (
        <SessionDrawer
          sessions={allSessions}
          activeId={targetSessionId}
          onPick={(s) => { navTo("p-flash-sess", { session_id: s.id }); setPickerOpen(false); }}
          onClose={() => setPickerOpen(false)}
        />
      )}

      {/* Top bar */}
      <div style={{
        display: "flex", alignItems: "center", gap: "8px",
        padding: "10px 12px 9px", flexShrink: 0,
        background: "var(--surface)", borderBottom: "1px solid var(--border)",
        position: "relative", zIndex: 10,
      }}>
        <button onClick={goBack} style={{
          width: "30px", height: "30px", borderRadius: "50%",
          background: "var(--surface2)", border: "1px solid var(--border)",
          display: "grid", placeItems: "center",
          fontSize: "18px", color: "var(--blue)", cursor: "pointer", flexShrink: 0,
        }}>‹</button>

        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "13px", fontWeight: 800, color: "var(--text)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
            ⚡ {sessionTitle}
          </div>
        </div>

        <button
          onClick={() => navTo("p-flash-overall", { session_id: targetSessionId })}
          style={{
            padding: "5px 10px", borderRadius: "999px",
            background: "color-mix(in srgb, var(--blue) 8%, transparent)",
            border: "1px solid color-mix(in srgb, var(--blue) 20%, transparent)",
            fontSize: "10px", fontWeight: 700, color: "var(--blue)",
            cursor: "pointer", flexShrink: 0, whiteSpace: "nowrap",
          }}
        >总资产 ›</button>

        <button
          onClick={() => setPickerOpen((v) => !v)}
          style={{
            width: "30px", height: "30px", borderRadius: "8px",
            background: pickerOpen ? "var(--blue10)" : "var(--surface2)",
            border: `1px solid ${pickerOpen ? "color-mix(in srgb, var(--blue) 30%, transparent)" : "var(--border)"}`,
            display: "grid", placeItems: "center",
            fontSize: "14px", color: pickerOpen ? "var(--blue)" : "var(--text2)",
            cursor: "pointer", flexShrink: 0,
          }}
          title="历史 Session"
        >≡</button>
      </div>

      {/* Chat area */}
      <div
        ref={scrollRef}
        className="no-scrollbar"
        style={{ flex: 1, overflowY: "auto", padding: "14px 12px 8px", display: "flex", flexDirection: "column", gap: "10px" }}
      >
        {isLoading && (
          <>
            {[1,2,3].map(i => (
              <div key={i} style={{
                height: "50px", borderRadius: "var(--r)",
                background: "var(--surface)", border: "1px solid var(--border)",
                animation: "pulse 1.4s ease-in-out infinite",
                animationDelay: `${i*0.12}s`,
                alignSelf: i % 2 === 0 ? "flex-end" : "flex-start",
                width: `${55 + i*8}%`,
              }} />
            ))}
            <style>{`@keyframes pulse{0%,100%{opacity:.6}50%{opacity:.3}}`}</style>
          </>
        )}

        {!isLoading && error && (
          <div style={{ textAlign: "center", color: "var(--red)", fontSize: "12px", padding: "32px 0" }}>{error}</div>
        )}

        {!isLoading && !error && messages.length === 0 && (
          <div style={{ textAlign: "center", padding: "40px 0", color: "var(--text3)", fontSize: "13px" }}>
            <div style={{ fontSize: "24px", marginBottom: "8px" }}>⚡</div>
            <div>发送一条闪念，Agent 会帮你整理记录</div>
          </div>
        )}

        {!isLoading && messages.map((msg) => (
          <MessageBubble key={msg.id} msg={msg} />
        ))}

        <div style={{ height: "4px", flexShrink: 0 }} />
      </div>

      {/* Input bar */}
      <div style={{
        flexShrink: 0, padding: "8px 12px 12px",
        background: "var(--surface)", borderTop: "1px solid var(--border)",
      }}>
        <div style={{ fontSize: "9px", color: "var(--text3)", marginBottom: "5px", fontWeight: 600 }}>
          <strong style={{ color: "var(--text2)" }}>{sessionTitle}</strong>
        </div>
        <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }}
            placeholder="说点什么…"
            style={{
              flex: 1, minWidth: 0, padding: "9px 14px",
              background: "var(--surface2)", border: "1px solid var(--border)",
              borderRadius: "999px", fontSize: "13px", color: "var(--text)", outline: "none",
            }}
          />
          <button
            onClick={send}
            disabled={!input.trim() || sending}
            style={{
              width: "36px", height: "36px", borderRadius: "50%",
              background: input.trim() ? "var(--grad)" : "var(--surface2)",
              border: "1px solid var(--border)",
              display: "grid", placeItems: "center",
              fontSize: "15px", color: input.trim() ? "#fff" : "var(--text3)",
              cursor: input.trim() ? "pointer" : "default", flexShrink: 0,
              boxShadow: input.trim() ? "0 2px 8px rgba(59,91,245,.3)" : "none",
            }}
          >{sending ? "…" : "✦"}</button>
        </div>
      </div>
    </div>
  );
}
