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

// Colors reference the accent tokens (not raw hex) so notification chips flip
// with the theme — the old dark-tuned light-blue/green/etc. fg were near
// invisible on the light-mode toast / bell / page.
const META: Record<string, NotifMeta> = {
  flash_done:  { icon: "⚡", fg: "var(--eu-accent-blue-fg)",   bg: "var(--eu-accent-blue-bg)",   edge: "var(--eu-accent-blue-edge)" },
  task_done:   { icon: "✓", fg: "var(--eu-accent-green-fg)",  bg: "var(--eu-accent-green-bg)",  edge: "var(--eu-accent-green-edge)" },
  task_failed: { icon: "!", fg: "var(--eu-accent-red-fg)",    bg: "var(--eu-accent-red-bg)",    edge: "var(--eu-accent-red-edge)" },
  reminder:    { icon: "⏰", fg: "var(--eu-accent-purple-fg)", bg: "var(--eu-accent-purple-bg)", edge: "var(--eu-accent-purple-edge)" },
};

const FALLBACK: NotifMeta = { icon: "•", fg: "var(--eu-accent-neutral-fg)", bg: "var(--eu-accent-neutral-bg)", edge: "var(--eu-accent-neutral-edge)" };

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
