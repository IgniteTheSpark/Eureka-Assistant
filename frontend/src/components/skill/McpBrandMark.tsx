/**
 * McpBrandMark — renders a third-party MCP's real brand logo as a self-contained
 * tile (brand-colored rounded square + white mark), for task / external_ref
 * cards. The card "icon" carries a sentinel like "mcp:dingtalk"; the renderers
 * (SkillCard.IconTile, AssetDetailDrawer hero) detect it via isMcpBrand and
 * render this instead of an emoji glyph.
 *
 * Only brands with a real mark live here (DingTalk). Notion / Google Calendar
 * stay as emoji stand-ins (📝 / 📅) until we add their marks too.
 */

interface Brand {
  bg: string;
  viewBox: string;
  /** Single white path, drawn on the brand-colored tile. */
  path: string;
}

const BRANDS: Record<string, Brand> = {
  // DingTalk 钉钉 — the official feathered-wing + lightning mark (Ant Design's
  // dingtalk icon) on the brand azure from the app icon.
  dingtalk: {
    bg: "#2EA7F7",
    viewBox: "0 0 1024 1024",
    path: "M573.7 252.5C422.5 197.4 201.3 96.7 201.3 96.7c-15.7-4.1-17.9 11.1-17.9 11.1c-5 61.1 33.6 160.5 53.6 182.8c19.9 22.3 319.1 113.7 319.1 113.7S326 357.9 270.5 341.9c-55.6-16-37.9 17.8-37.9 17.8c11.4 61.7 64.9 131.8 107.2 138.4c42.2 6.6 220.1 4 220.1 4s-35.5 4.1-93.2 11.9c-42.7 5.8-97 12.5-111.1 17.8c-33.1 12.5 24 62.6 24 62.6c84.7 76.8 129.7 50.5 129.7 50.5c33.3-10.7 61.4-18.5 85.2-24.2L565 743.1h84.6L603 928l205.3-271.9H700.8l22.3-38.7c.3.5.4.8.4.8S799.8 496.1 829 433.8l.6-1h-.1c5-10.8 8.6-19.7 10-25.8c17-71.3-114.5-99.4-265.8-154.5",
  },
};

/** "mcp:dingtalk" → "dingtalk" (only when a real brand mark exists). */
function brandKey(icon: string): string | null {
  if (!icon || !icon.startsWith("mcp:")) return null;
  const k = icon.slice(4);
  return BRANDS[k] ? k : null;
}

export function isMcpBrand(icon: string | undefined | null): boolean {
  return !!icon && brandKey(icon) !== null;
}

export function McpBrandMark({
  icon, size, radius,
}: { icon: string; size: number; radius: number }) {
  const key = brandKey(icon);
  if (!key) return null;
  const b = BRANDS[key];
  const mark = Math.round(size * 0.62);
  return (
    <div
      className="shrink-0 flex items-center justify-center"
      style={{ width: size, height: size, borderRadius: radius, background: b.bg }}
      aria-hidden="true"
    >
      <svg viewBox={b.viewBox} width={mark} height={mark} fill="#ffffff">
        <path d={b.path} />
      </svg>
    </div>
  );
}
