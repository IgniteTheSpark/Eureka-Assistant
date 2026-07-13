"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { api } from "@/lib/api";
import type { ChatMessage } from "@/lib/types";

const LS_KEY = "eureka_agent_session_id";

let msgCounter = 0;
function newId() {
  return `msg-${++msgCounter}-${Date.now()}`;
}

function loadSessionId(): string {
  if (typeof window === "undefined") return "";
  return localStorage.getItem(LS_KEY) ?? "";
}

function saveSessionId(id: string) {
  if (typeof window === "undefined") return;
  if (id) localStorage.setItem(LS_KEY, id);
  else localStorage.removeItem(LS_KEY);
}

export function useAgentChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  const sessionIdRef = useRef<string>(loadSessionId());
  const messagesRef = useRef<ChatMessage[]>([]);

  // Load previous session messages on mount
  useEffect(() => {
    const savedId = sessionIdRef.current;
    if (!savedId) return;
    setIsLoadingHistory(true);
    api.getSessionMessages(savedId).then((res) => {
      if (res.ok && res.messages.length > 0) {
        const loaded: ChatMessage[] = res.messages.map((m) => ({
          id: m.id,
          role: m.role,
          text: m.text,
          cards: (m.cards as ChatMessage["cards"]) ?? [],
          elapsed_ms: m.elapsed_ms,
        }));
        messagesRef.current = loaded;
        setMessages(loaded);
      }
    }).finally(() => setIsLoadingHistory(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loadSession = useCallback(async (sessionId: string) => {
    setIsLoadingHistory(true);
    sessionIdRef.current = sessionId;
    saveSessionId(sessionId);
    const res = await api.getSessionMessages(sessionId);
    if (res.ok) {
      const loaded: ChatMessage[] = res.messages.map((m) => ({
        id: m.id,
        role: m.role,
        text: m.text,
        cards: (m.cards as ChatMessage["cards"]) ?? [],
        elapsed_ms: m.elapsed_ms,
      }));
      messagesRef.current = loaded;
      setMessages(loaded);
    }
    setIsLoadingHistory(false);
  }, []);

  const sendMessage = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed || isLoading) return;

    const history = messagesRef.current.slice(-10).map((m) => ({
      role: m.role as "user" | "agent",
      text: m.text,
    }));

    const userMsg: ChatMessage = {
      id: newId(),
      role: "user",
      text: trimmed,
    };
    messagesRef.current = [...messagesRef.current, userMsg];
    setMessages((prev) => [...prev, userMsg]);
    setIsLoading(true);

    try {
      const res = await api.askAgent(trimmed, sessionIdRef.current || undefined, history);
      if (res.ok && res.session_id && !sessionIdRef.current) {
        sessionIdRef.current = res.session_id;
        saveSessionId(res.session_id);
      }
      const agentMsg: ChatMessage = {
        id: newId(),
        role: "agent",
        text:
          res.ok
            ? res.answer || res.summary || (res.cards?.length ? "好的，已为你创建：" : "（无回复）")
            : `错误: ${res.error ?? "未知错误"}`,
        cards: res.cards,
        elapsed_ms: res.elapsed_ms,
        input_tokens: res.input_tokens,
        output_tokens: res.output_tokens,
        error: !res.ok,
      };
      messagesRef.current = [...messagesRef.current, agentMsg];
      setMessages((prev) => [...prev, agentMsg]);
    } catch (err) {
      const agentMsg: ChatMessage = {
        id: newId(),
        role: "agent",
        text: `网络错误: ${String(err)}`,
        error: true,
      };
      messagesRef.current = [...messagesRef.current, agentMsg];
      setMessages((prev) => [...prev, agentMsg]);
    } finally {
      setIsLoading(false);
    }
  }, [isLoading]);

  const clearMessages = useCallback(() => {
    setMessages([]);
    messagesRef.current = [];
    sessionIdRef.current = "";
    saveSessionId("");
  }, []);

  return { messages, isLoading, isLoadingHistory, sendMessage, clearMessages, loadSession };
}
