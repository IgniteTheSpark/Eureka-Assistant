import { Bell, Sun, Moon } from "lucide-react";
import { useNavigate } from "react-router-dom";

import { useTheme } from "@/context/ThemeContext";
import { useNotifications } from "@/hooks/useNotifications";

/**
 * HeaderControls — the top-right cluster for pages that own their own header
 * (Calendar, Library). Two affordances:
 *   - 🔔 notification bell → /notifications, with an unread badge (the
 *     notifications page is otherwise unreachable now that the dock dropped it).
 *   - ☀ / 🌙 light–dark toggle (ThemeContext).
 *
 * All colors are tokens so the cluster itself flips correctly between themes.
 */
export function HeaderControls() {
  const navigate = useNavigate();
  const { unread } = useNotifications();
  const { theme, toggle } = useTheme();

  const btn: React.CSSProperties = {
    width: 32, height: 32, borderRadius: 999,
    display: "grid", placeItems: "center", cursor: "pointer",
    background: "var(--eu-surface)",
    border: "1px solid var(--eu-border)",
    color: "var(--eu-text-mid)",
  };

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        aria-label="通知"
        title="通知"
        onClick={() => navigate("/notifications")}
        style={{ ...btn, position: "relative" }}
      >
        <Bell size={15} strokeWidth={1.75} />
        {unread > 0 && (
          <span
            style={{
              position: "absolute", top: -2, right: -2,
              minWidth: 15, height: 15, padding: "0 4px", borderRadius: 999,
              background: "var(--eu-accent-red-solid)", color: "#fff",
              fontSize: 9.5, fontWeight: 700, lineHeight: 1,
              display: "grid", placeItems: "center",
            }}
          >
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>

      <button
        type="button"
        aria-label={theme === "dark" ? "切换到日间模式" : "切换到夜间模式"}
        title={theme === "dark" ? "日间模式" : "夜间模式"}
        onClick={toggle}
        style={btn}
      >
        {theme === "dark"
          ? <Sun size={15} strokeWidth={1.75} />
          : <Moon size={15} strokeWidth={1.75} />}
      </button>
    </div>
  );
}
