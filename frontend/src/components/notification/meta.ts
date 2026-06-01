import type { Notification } from "@/lib/types";

/**
 * Per-type presentation for notifications, shared by Toast / Bell / Page so a
 * given type always looks the same. Colors are inline (not token classes) so
 * the same map works in both Tailwind-class and style-object contexts.
 */
export interface NotifMeta {
  icon: string;
  fg: string;
  bg: string;
  edge: string;
}

const META: Record<string, NotifMeta> = {
  flash_done:  { icon: "⚡", fg: "#a4c2ff", bg: "rgba(111,158,255,0.12)", edge: "rgba(111,158,255,0.28)" },
  task_done:   { icon: "✓", fg: "#86e0a5", bg: "rgba(134,224,165,0.12)", edge: "rgba(134,224,165,0.28)" },
  task_failed: { icon: "!", fg: "#ff9b9b", bg: "rgba(255,138,138,0.12)", edge: "rgba(255,138,138,0.30)" },
  reminder:    { icon: "⏰", fg: "#c4a8ff", bg: "rgba(196,168,255,0.12)", edge: "rgba(196,168,255,0.28)" },
};

const FALLBACK: NotifMeta = { icon: "•", fg: "#d4dbe6", bg: "rgba(212,219,230,0.08)", edge: "rgba(212,219,230,0.18)" };

export function notifMeta(type: string): NotifMeta {
  return META[type] ?? FALLBACK;
}

/** Where tapping a notification should take the user (null = no nav). */
export function notifLinkTarget(n: Notification): string | null {
  if (!n.link) return null;
  // M7 reminder links are structured: "reminder:evt:<id>:<thr>" / "reminder:todo:..".
  if (n.link.startsWith("reminder:evt:")) return "/calendar";
  if (n.link.startsWith("reminder:todo:")) return "/library/todo";
  // M6 task/flash links carry an opaque asset id; the library resolves it.
  return "/library";
}

/**
 * Handle a notification tap — centralizes nav for Toast / Bell / Page so they
 * behave identically. flash_done opens the captured flash SESSION in chat
 * (link carries the session id); everything else falls back to notifLinkTarget.
 */
export function notifNavigate(n: Notification, navigate: (to: string) => void): void {
  if (n.type === "flash_done" && n.link) {
    // Open the flash session that this capture landed in.
    window.localStorage.setItem("eureka:active_chat_session", n.link);
    navigate("/chat");
    return;
  }
  const target = notifLinkTarget(n);
  if (target) navigate(target);
}

export function relativeTime(iso: string | null): string {
  if (!iso) return "";
  const diffSec = Math.max(0, Math.floor((Date.now() - +new Date(iso)) / 1000));
  if (diffSec < 60) return "刚刚";
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)} 分钟前`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)} 小时前`;
  if (diffSec < 86400 * 7) return `${Math.floor(diffSec / 86400)} 天前`;
  const d = new Date(iso);
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}
