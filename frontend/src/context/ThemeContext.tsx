import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";

/**
 * ThemeContext — light / dark switching.
 *
 * Themes are CSS-variable palettes selected by an `html` class (see
 * tokens.css): dark = `theme-atmosphere`, light = `theme-light`. The provider
 * is the single owner of that class + the iOS `theme-color` meta, and persists
 * the choice in localStorage. Default is dark (the app's original look) — the
 * user opts into light via the header toggle.
 *
 * Fail-soft: no provider (unit tests) → hook returns a dark no-op.
 */
export type Theme = "dark" | "light";

const THEME_CLASS: Record<Theme, string> = {
  dark:  "theme-atmosphere",
  light: "theme-light",
};
const THEME_META: Record<Theme, string> = {
  dark:  "#0b1220",   // --eu-bg (atmosphere)
  light: "#f4f2ec",   // --eu-bg (light)
};
const STORAGE_KEY = "eureka:theme";

interface ThemeContextValue {
  theme: Theme;
  setTheme: (t: Theme) => void;
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

function readStored(): Theme {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (v === "light" || v === "dark") return v;
  } catch { /* ignore */ }
  return "dark";
}

/** Swap the html theme class + theme-color meta. Idempotent. */
function applyTheme(theme: Theme) {
  const el = document.documentElement;
  el.classList.remove("theme-atmosphere", "theme-light", "theme-lab");
  el.classList.add(THEME_CLASS[theme]);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", THEME_META[theme]);
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  // Apply synchronously in the initializer so the first paint already matches
  // the stored theme (no dark→light flash on reload when light is saved).
  const [theme, setThemeState] = useState<Theme>(() => {
    const t = readStored();
    applyTheme(t);
    return t;
  });

  useEffect(() => { applyTheme(theme); }, [theme]);

  function setTheme(t: Theme) {
    try { localStorage.setItem(STORAGE_KEY, t); } catch { /* ignore */ }
    setThemeState(t);
  }

  return (
    <ThemeContext.Provider value={{ theme, setTheme, toggle: () => setTheme(theme === "dark" ? "light" : "dark") }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  return ctx ?? { theme: "dark", setTheme: () => {}, toggle: () => {} };
}
