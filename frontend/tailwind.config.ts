import type { Config } from "tailwindcss";

/**
 * Tailwind config — bridges Eureka design tokens (--eu-*) into utility classes.
 *
 * Tokens live in `src/styles/tokens.css` (copied from docs/rebuild/design-tokens.css).
 * Edit tokens there; this config maps them into Tailwind so `text-eu-text-hi`
 * `bg-eu-surface` `rounded-eu-md` etc. work in components.
 *
 * Adding a new token:
 *   1. Add `--eu-x: …` to tokens.css
 *   2. Reference it here via `"var(--eu-x)"`
 *   3. Use `eu-x` everywhere in components
 */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  darkMode: ["class", ".theme-atmosphere"], // single theme for MVP
  theme: {
    extend: {
      colors: {
        "eu-bg":              "var(--eu-bg)",
        "eu-surface":         "var(--eu-surface)",
        "eu-surface-raised":  "var(--eu-surface-raised)",
        "eu-surface-hover":   "var(--eu-surface-hover)",
        "eu-border":          "var(--eu-border)",
        "eu-border-strong":   "var(--eu-border-strong)",
        "eu-rule":            "var(--eu-rule)",
        "eu-text":            "var(--eu-text)",
        "eu-text-hi":         "var(--eu-text-hi)",
        "eu-text-mid":        "var(--eu-text-mid)",
        "eu-text-lo":         "var(--eu-text-lo)",
        "eu-text-muted":      "var(--eu-text-muted)",
        "eu-brand":           "var(--eu-brand)",
        "eu-brand-hi":        "var(--eu-brand-hi)",
        "eu-brand-faint":     "var(--eu-brand-faint)",
        "eu-brand-line":      "var(--eu-brand-line)",
        "eu-brand-glow":      "var(--eu-brand-glow)",

        // Status colors
        "eu-success": "var(--eu-success)",
        "eu-warning": "var(--eu-warning)",
        "eu-error":   "var(--eu-error)",
        "eu-info":    "var(--eu-info)",

        // Accent palette — 7 slots × {bg, edge, fg, solid}
        // Used by SkillCard's accent_color + meta_field badge variants.
        "eu-accent": {
          blue:    { bg: "var(--eu-accent-blue-bg)",    edge: "var(--eu-accent-blue-edge)",    fg: "var(--eu-accent-blue-fg)",    solid: "var(--eu-accent-blue-solid)"    },
          purple:  { bg: "var(--eu-accent-purple-bg)",  edge: "var(--eu-accent-purple-edge)",  fg: "var(--eu-accent-purple-fg)",  solid: "var(--eu-accent-purple-solid)"  },
          amber:   { bg: "var(--eu-accent-amber-bg)",   edge: "var(--eu-accent-amber-edge)",   fg: "var(--eu-accent-amber-fg)",   solid: "var(--eu-accent-amber-solid)"   },
          green:   { bg: "var(--eu-accent-green-bg)",   edge: "var(--eu-accent-green-edge)",   fg: "var(--eu-accent-green-fg)",   solid: "var(--eu-accent-green-solid)"   },
          red:     { bg: "var(--eu-accent-red-bg)",     edge: "var(--eu-accent-red-edge)",     fg: "var(--eu-accent-red-fg)",     solid: "var(--eu-accent-red-solid)"     },
          gray:    { bg: "var(--eu-accent-gray-bg)",    edge: "var(--eu-accent-gray-edge)",    fg: "var(--eu-accent-gray-fg)",    solid: "var(--eu-accent-gray-solid)"    },
          neutral: { bg: "var(--eu-accent-neutral-bg)", edge: "var(--eu-accent-neutral-edge)", fg: "var(--eu-accent-neutral-fg)", solid: "var(--eu-accent-neutral-solid)" },
        },
      },
      fontFamily: {
        sans:    ["var(--eu-font-sans)"],
        mono:    ["var(--eu-font-mono)"],
        display: ["var(--eu-font-display)"],
      },
      fontSize: {
        "eu-xs":   "var(--eu-fs-xs)",
        "eu-sm":   "var(--eu-fs-sm)",
        "eu-base": "var(--eu-fs-base)",
        "eu-md":   "var(--eu-fs-md)",
        "eu-lg":   "var(--eu-fs-lg)",
        "eu-xl":   "var(--eu-fs-xl)",
        "eu-2xl":  "var(--eu-fs-2xl)",
        "eu-3xl":  "var(--eu-fs-3xl)",
        "eu-4xl":  "var(--eu-fs-4xl)",
      },
      spacing: {
        "eu-xs":  "var(--eu-sp-xs)",
        "eu-sm":  "var(--eu-sp-sm)",
        "eu-md":  "var(--eu-sp-md)",
        "eu-lg":  "var(--eu-sp-lg)",
        "eu-xl":  "var(--eu-sp-xl)",
        "eu-2xl": "var(--eu-sp-2xl)",
        "eu-3xl": "var(--eu-sp-3xl)",
        "eu-4xl": "var(--eu-sp-4xl)",
      },
      borderRadius: {
        "eu-sm":   "var(--eu-r-sm)",
        "eu-md":   "var(--eu-r-md)",
        "eu-lg":   "var(--eu-r-lg)",
        "eu-xl":   "var(--eu-r-xl)",
        "eu-full": "var(--eu-r-full)",
      },
      boxShadow: {
        "eu-sm": "var(--eu-shadow-sm)",
        "eu-md": "var(--eu-shadow-md)",
        "eu-lg": "var(--eu-shadow-lg)",
      },
      transitionDuration: {
        "eu-fast":   "var(--eu-dur-fast)",
        "eu-normal": "var(--eu-dur-normal)",
        "eu-slow":   "var(--eu-dur-slow)",
      },
      transitionTimingFunction: {
        "eu-in":     "var(--eu-ease-in)",
        "eu-out":    "var(--eu-ease-out)",
        "eu-in-out": "var(--eu-ease-in-out)",
      },
    },
  },
  plugins: [],
} satisfies Config;
