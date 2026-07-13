"use client";

import { useState, useRef, useEffect, type KeyboardEvent } from "react";
import { useNav } from "@/context/NavContext";
import { useAgentChat } from "@/hooks/useAgentChat";
import MarkdownText from "@/components/ui/MarkdownText";
import { api } from "@/lib/api";
import type { Card, ChatMessage, Session } from "@/lib/types";

const SUGGESTIONS = [
  "今天有什么待办事项？",
  "帮我总结最近的会议",
  "有哪些未跟进的联系人？",
  "分析我的支出情况",
];

// ── Asset card (shown inside agent response when MCP created an asset) ──────────

const CARD_ICONS: Record<string, string> = {
  todo: "✅", expense: "💰", idea: "💡", note: "📄", contact: "👤", misc: "📎",
};

function AssetCard({ card, msgId }: { card: Card; msgId?: string }) {
  const { navTo } = useNav();

  const handleClick = () => {
    if (card.asset_id) {
      navTo("p-asset-detail", {
        asset_id: card.asset_id,
        from_page: "p-agent-chat",
        from_msg_id: msgId ?? "",
      });
    } else if (card.session_id) {
      navTo("p-flash-sess", { session_id: card.session_id });
    }
  };

  const isNavigable = !!(card.asset_id || card.session_id);

  return (
    <div
      onClick={isNavigable ? handleClick : undefined}
      style={{
        background: "var(--surface)",
        border: "1px solid var(--border)",
        borderRadius: "var(--rs)",
        padding: "9px 12px",
        boxShadow: "var(--sh-s)",
        cursor: isNavigable ? "pointer" : "default",
        display: "flex",
        alignItems: "center",
        gap: "8px",
      }}
    >
      <span style={{ fontSize: "14px" }}>
        {CARD_ICONS[card.type] ?? "📦"}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        {card.title && (
          <div style={{
            fontSize: "12px", fontWeight: 600, color: "var(--text)",
            overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
          }}>
            {card.title}
          </div>
        )}
        {card.subtitle && (
          <div style={{
            fontSize: "10px", color: "var(--text3)", marginTop: "1px",
            overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
          }}>
            {card.subtitle}
          </div>
        )}
      </div>
      {isNavigable && <span style={{ color: "var(--text3)", fontSize: "13px" }}>›</span>}
    </div>
  );
}

// ── MetaLine ────────────────────────────────────────────────────────────────────

function MetaLine({
  elapsed_ms,
  input_tokens,
  output_tokens,
}: {
  elapsed_ms?: number;
  input_tokens?: number;
  output_tokens?: number;
}) {
  if (!elapsed_ms && !input_tokens && !output_tokens) return null;
  const secs = elapsed_ms ? (elapsed_ms / 1000).toFixed(1) : null;
  return (
    <div
      style={{
        fontSize: "10px",
        color: "var(--text3)",
        marginTop: "5px",
        display: "flex",
        alignItems: "center",
        gap: "6px",
      }}
    >
      {secs && <span>⏱ {secs}s</span>}
      {!!(input_tokens || output_tokens) && (
        <span>输入 {input_tokens ?? 0} · 输出 {output_tokens ?? 0} tokens</span>
      )}
    </div>
  );
}

// ── MessageBubble ───────────────────────────────────────────────────────────────

function MessageBubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === "user";

  if (isUser) {
    return (
      <div style={{ display: "flex", justifyContent: "flex-end", marginBottom: "10px" }}>
        <div
          style={{
            maxWidth: "78%",
            padding: "10px 14px",
            borderRadius: "18px 18px 4px 18px",
            background: "var(--grad)",
            color: "#fff",
            fontSize: "13px",
            lineHeight: 1.6,
            boxShadow: "0 2px 10px rgba(59,91,245,.3)",
          }}
        >
          {msg.text}
        </div>
      </div>
    );
  }

  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: "8px",
        marginBottom: "14px",
      }}
    >
      {/* Agent avatar */}
      <div
        style={{
          width: "30px",
          height: "30px",
          borderRadius: "50%",
          background: "var(--grad)",
          display: "grid",
          placeItems: "center",
          fontSize: "14px",
          color: "#fff",
          flexShrink: 0,
          marginTop: "2px",
          boxShadow: "0 2px 8px rgba(59,91,245,.3)",
        }}
      >
        ✦
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            background: msg.error ? "rgba(220,38,38,.06)" : "var(--surface)",
            border: `1px solid ${msg.error ? "rgba(220,38,38,.2)" : "var(--border)"}`,
            borderRadius: "4px 18px 18px 18px",
            padding: "10px 14px",
            boxShadow: "var(--sh-s)",
          }}
        >
          {msg.error ? (
            <span style={{ fontSize: "13px", color: "var(--red)" }}>{msg.text}</span>
          ) : (
            <MarkdownText text={msg.text} />
          )}
        </div>

        {/* Asset cards — created by agent via MCP; tappable when asset_id is present */}
        {msg.cards && msg.cards.length > 0 && (
          <div style={{ marginTop: "8px", display: "flex", flexDirection: "column", gap: "6px" }}>
            {msg.cards.map((card, i) => (
              <AssetCard key={i} card={card} msgId={msg.id} />
            ))}
          </div>
        )}

        <MetaLine elapsed_ms={msg.elapsed_ms} input_tokens={msg.input_tokens} output_tokens={msg.output_tokens} />
      </div>
    </div>
  );
}

// ── Sessions Drawer ─────────────────────────────────────────────────────────────
// Shows all historical sessions fetched from /api/sessions (not chat message history)

const SESSION_ICONS: Record<string, string> = {
  agent_chat: "✦",
  daily: "📅",
  meeting: "🎙",
  research: "🔍",
};

function formatSessionDate(dateStr: string | null, createdAt: string): string {
  const src = dateStr ?? createdAt;
  try {
    const d = new Date(src);
    const y = d.getFullYear();
    const mo = String(d.getMonth() + 1).padStart(2, "0");
    const da = String(d.getDate()).padStart(2, "0");
    return `${y}-${mo}-${da}`;
  } catch {
    return src;
  }
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div style={{
      fontSize: "9px", fontWeight: 700, color: "var(--text3)",
      letterSpacing: "0.08em", padding: "10px 2px 4px",
      textTransform: "uppercase",
    }}>{children}</div>
  );
}

function SessionRow({ s, onClick }: { s: Session; onClick: () => void }) {
  const isFlash = s.session_type === "daily";
  const iconColor = isFlash ? "var(--amber)" : "var(--blue)";
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "10px",
        padding: "10px 12px",
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--rs)", boxShadow: "var(--sh-s)", cursor: "pointer",
      }}
    >
      <div style={{
        width: "28px", height: "28px", borderRadius: "8px",
        background: `color-mix(in srgb, ${iconColor} 12%, transparent)`,
        border: `1px solid color-mix(in srgb, ${iconColor} 22%, transparent)`,
        display: "grid", placeItems: "center", fontSize: "13px", flexShrink: 0,
      }}>
        {SESSION_ICONS[s.session_type] ?? "📋"}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: "12px", fontWeight: 600, color: "var(--text)",
          overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
        }}>
          {s.title ?? `对话 ${s.id.slice(0, 8)}`}
        </div>
        <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
          {formatSessionDate(s.date ?? null, s.created_at)}
        </div>
      </div>
      <span style={{ fontSize: "14px", color: "var(--text3)", flexShrink: 0 }}>›</span>
    </div>
  );
}

function SessionsDrawer({
  onClose,
  onNewSession,
  onLoadSession,
}: {
  onClose: () => void;
  onNewSession: () => void;
  onLoadSession: (id: string) => void;
}) {
  const { navTo } = useNav();
  const [sessions, setSessions] = useState<Session[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setIsLoading(true);
    api.getSessions()
      .then((res) => {
        if (res.ok) setSessions(res.sessions ?? []);
        else setError(res.error ?? "加载失败");
      })
      .catch((e) => setError(String(e)))
      .finally(() => setIsLoading(false));
  }, []);

  const flashSessions   = sessions.filter(s => s.session_type === "daily");
  const agentSessions   = sessions.filter(s => s.session_type === "agent_chat");

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: "absolute", inset: 0,
          background: "rgba(10,14,30,.4)",
          zIndex: 40, backdropFilter: "blur(2px)",
        }}
      />
      {/* Panel */}
      <div
        style={{
          position: "absolute", top: 0, right: 0, bottom: 0, width: "78%",
          background: "var(--surface)", zIndex: 50,
          display: "flex", flexDirection: "column",
          boxShadow: "-4px 0 20px rgba(15,23,42,.18)",
        }}
      >
        {/* Header */}
        <div style={{
          padding: "14px 14px 10px", borderBottom: "1px solid var(--border)",
          display: "flex", alignItems: "center", gap: "8px", flexShrink: 0,
        }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>记录</div>
          </div>
          <button
            onClick={onClose}
            style={{
              width: "28px", height: "28px", borderRadius: "50%",
              background: "var(--surface2)", border: "1px solid var(--border)",
              display: "grid", placeItems: "center", fontSize: "16px",
              color: "var(--text3)", cursor: "pointer",
            }}
          >×</button>
        </div>

        {/* Body */}
        <div className="no-scrollbar" style={{ flex: 1, overflowY: "auto", padding: "4px 12px 16px" }}>
          {isLoading && (
            <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginTop: "12px" }}>
              {[1, 2, 3].map(i => (
                <div key={i} style={{
                  height: "54px", borderRadius: "var(--rs)",
                  background: "var(--surface2)", border: "1px solid var(--border)",
                  opacity: 1 - i * 0.25,
                }} />
              ))}
            </div>
          )}
          {!isLoading && error && (
            <div style={{ textAlign: "center", color: "var(--red)", fontSize: "12px", marginTop: "32px" }}>{error}</div>
          )}

          {!isLoading && !error && (
            <>
              {/* ── 问答对话 section ── */}
              <SectionLabel>问答对话</SectionLabel>

              {/* New session button */}
              <button
                onClick={() => { onNewSession(); onClose(); }}
                style={{
                  width: "100%", display: "flex", alignItems: "center", gap: "8px",
                  padding: "10px 12px", marginBottom: "6px",
                  background: "color-mix(in srgb, var(--blue) 6%, transparent)",
                  border: "1px dashed color-mix(in srgb, var(--blue) 40%, transparent)",
                  borderRadius: "var(--rs)", cursor: "pointer",
                  fontSize: "12px", fontWeight: 600, color: "var(--blue)",
                }}
              >
                <span style={{ fontSize: "16px" }}>＋</span> 新建会话
              </button>

              {agentSessions.length === 0 && (
                <div style={{ fontSize: "11px", color: "var(--text3)", padding: "6px 2px" }}>暂无对话记录</div>
              )}
              <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                {agentSessions.map(s => (
                  <SessionRow key={s.id} s={s} onClick={() => {
                    onLoadSession(s.id);
                    onClose();
                  }} />
                ))}
              </div>

              {/* ── 闪念记录 section ── */}
              {flashSessions.length > 0 && (
                <>
                  <SectionLabel>闪念记录</SectionLabel>
                  <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                    {flashSessions.map(s => (
                      <SessionRow key={s.id} s={s} onClick={() => {
                        onClose();
                        navTo("p-flash-sess", { session_id: s.id });
                      }} />
                    ))}
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </>
  );
}

// ── Main Page ───────────────────────────────────────────────────────────────────

export default function AgentChatPage() {
  const { goBack } = useNav();
  const { messages, isLoading, isLoadingHistory, sendMessage, clearMessages, loadSession } = useAgentChat();
  const [inputText, setInputText] = useState("");
  const [historyOpen, setHistoryOpen] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isLoading]);

  function handleSend() {
    const text = inputText.trim();
    if (!text || isLoading || isLoadingHistory) return;
    setInputText("");
    sendMessage(text);
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  }

  const showSuggestions = messages.length === 0 && !isLoadingHistory;

  return (
    <div
      style={{
        display: "flex", flexDirection: "column",
        flex: 1, minHeight: 0, background: "var(--bg)",
        position: "relative",
      }}
    >
      {/* Sessions drawer — shows all historical sessions from the DB */}
      {historyOpen && (
        <SessionsDrawer
          onClose={() => setHistoryOpen(false)}
          onNewSession={clearMessages}
          onLoadSession={loadSession}
        />
      )}

      {/* Top bar */}
      <div
        style={{
          display: "flex", alignItems: "center", gap: "10px",
          padding: "12px 14px 10px", flexShrink: 0,
          background: "var(--surface)", borderBottom: "1px solid var(--border)",
        }}
      >
        <button
          onClick={goBack}
          style={{
            width: "32px", height: "32px", borderRadius: "50%",
            background: "var(--surface2)", border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "18px", color: "var(--blue)", flexShrink: 0, cursor: "pointer",
          }}
          title="返回"
        >
          ‹
        </button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: "16px", fontWeight: 800, color: "var(--text)", letterSpacing: "-0.02em" }}>
            ✦ Ask Agent
          </div>
          <div style={{ fontSize: "10px", color: "var(--text3)", marginTop: "1px" }}>
            Eureka 3.0 · 智能问答
            {messages.length > 0 && ` · ${Math.floor(messages.length / 2)} 轮对话`}
          </div>
        </div>
        <button
          onClick={() => setHistoryOpen(true)}
          style={{
            width: "30px", height: "30px", borderRadius: "50%",
            background: historyOpen ? "var(--blue10)" : "var(--surface2)",
            border: `1px solid ${historyOpen ? "var(--blue)" : "var(--border)"}`,
            display: "grid", placeItems: "center",
            fontSize: "16px", color: historyOpen ? "var(--blue)" : "var(--text3)",
            cursor: "pointer",
          }}
          title="对话历史"
        >
          ☰
        </button>
      </div>

      {/* Chat area */}
      <div
        className="no-scrollbar"
        style={{
          flex: 1, overflowY: "auto", overflowX: "hidden",
          padding: "16px 14px 8px",
          WebkitOverflowScrolling: "touch",
        }}
      >
        {/* History loading skeleton */}
        {isLoadingHistory && (
          <div style={{ display: "flex", flexDirection: "column", gap: "10px", padding: "8px 0" }}>
            {[1, 2, 3].map(i => (
              <div key={i} style={{
                height: "48px", borderRadius: "var(--r)",
                background: "var(--surface)", border: "1px solid var(--border)",
                opacity: 1 - i * 0.2,
                alignSelf: i % 2 === 0 ? "flex-end" : "flex-start",
                width: `${50 + i * 12}%`,
              }} />
            ))}
          </div>
        )}

        {/* Suggestion chips (before first message) */}
        {showSuggestions && (
          <div style={{ marginBottom: "20px" }}>
            <div
              style={{
                display: "flex", flexDirection: "column", alignItems: "center",
                padding: "20px 0 16px", gap: "8px", textAlign: "center",
              }}
            >
              <div
                style={{
                  width: "56px", height: "56px", borderRadius: "50%",
                  background: "var(--grad)", display: "grid", placeItems: "center",
                  fontSize: "26px", color: "#fff",
                  boxShadow: "0 4px 16px rgba(59,91,245,.4)",
                }}
              >
                ✦
              </div>
              <div style={{ fontSize: "15px", fontWeight: 700, color: "var(--text)" }}>
                你好，我是 Eureka Agent
              </div>
              <div style={{ fontSize: "12px", color: "var(--text2)", lineHeight: 1.6 }}>
                我可以帮你检索记录、总结会议、<br />追踪待办事项和联系人
              </div>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px" }}>
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => { setInputText(s); inputRef.current?.focus(); }}
                  style={{
                    padding: "10px 12px",
                    background: "var(--surface)", border: "1px solid var(--border)",
                    borderRadius: "var(--r)", fontSize: "11px", fontWeight: 600,
                    color: "var(--text2)", cursor: "pointer",
                    textAlign: "left", lineHeight: 1.5,
                    boxShadow: "var(--sh-s)", transition: "all .15s",
                  }}
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Messages */}
        {messages.map((msg) => (
          <MessageBubble key={msg.id} msg={msg} />
        ))}

        {/* Loading dots */}
        {isLoading && (
          <div style={{ display: "flex", alignItems: "flex-start", gap: "8px", marginBottom: "14px" }}>
            <div
              style={{
                width: "30px", height: "30px", borderRadius: "50%",
                background: "var(--grad)", display: "grid", placeItems: "center",
                fontSize: "14px", color: "#fff", flexShrink: 0,
              }}
            >
              ✦
            </div>
            <div
              style={{
                background: "var(--surface)", border: "1px solid var(--border)",
                borderRadius: "4px 18px 18px 18px",
                padding: "10px 16px", boxShadow: "var(--sh-s)",
                display: "flex", alignItems: "center", gap: "5px",
              }}
            >
              {[0, 1, 2].map((i) => (
                <span
                  key={i}
                  style={{
                    width: "6px", height: "6px", borderRadius: "50%",
                    background: "var(--blue)", display: "inline-block",
                    animation: `bounce 1.2s ease-in-out ${i * 0.2}s infinite`,
                  }}
                />
              ))}
              <style>{`
                @keyframes bounce {
                  0%, 80%, 100% { transform: scale(0.6); opacity: 0.4; }
                  40% { transform: scale(1); opacity: 1; }
                }
              `}</style>
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input bar */}
      <div
        style={{
          flexShrink: 0, borderTop: "1px solid var(--border)",
          background: "var(--surface)", padding: "10px 12px",
          display: "flex", alignItems: "center", gap: "10px",
        }}
      >
        <input
          ref={inputRef}
          type="text"
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="问 Agent 任何问题…"
          disabled={isLoading}
          style={{
            flex: 1, minWidth: 0,
            fontSize: "13px", color: "var(--text)",
            background: "var(--surface2)", border: "1px solid var(--border)",
            borderRadius: "999px", padding: "10px 16px",
            outline: "none", caretColor: "var(--blue)",
            opacity: isLoading ? 0.6 : 1,
          }}
        />
        <button
          onClick={handleSend}
          disabled={!inputText.trim() || isLoading}
          style={{
            width: "40px", height: "40px", borderRadius: "50%",
            background: inputText.trim() && !isLoading ? "var(--grad)" : "var(--surface2)",
            border: "1px solid var(--border)",
            display: "grid", placeItems: "center",
            fontSize: "16px",
            color: inputText.trim() && !isLoading ? "#fff" : "var(--text3)",
            flexShrink: 0,
            boxShadow: inputText.trim() && !isLoading ? "0 4px 14px rgba(59,91,245,.4)" : "none",
            cursor: inputText.trim() && !isLoading ? "pointer" : "default",
            transition: "all .15s",
          }}
          title="发送"
        >
          ➤
        </button>
      </div>
    </div>
  );
}
