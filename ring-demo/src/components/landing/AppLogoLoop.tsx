export type AppLogoKind =
  | "chrome"
  | "claude"
  | "codex"
  | "cursor"
  | "dingtalk"
  | "eurekamind"
  | "figma"
  | "github"
  | "lark"
  | "more"
  | "netease"
  | "notion"
  | "slack"
  | "spotify"
  | "telegram"
  | "trae"
  | "wechat"
  | "wisenote"
  | "vscode";

export interface AppLogoItem {
  alt?: string;
  kind: AppLogoKind;
  name: string;
  src?: string;
}

interface AppLogoLoopProps {
  rows: readonly (readonly AppLogoItem[])[];
}

function AppLogoMark({ kind }: { kind: AppLogoKind }) {
  if (kind === "figma") {
    return (
      <span aria-hidden="true" className="app-logo-mark app-logo-mark-figma">
        <i /><i /><i /><i /><i />
      </span>
    );
  }

  if (kind === "slack") {
    return (
      <span aria-hidden="true" className="app-logo-mark app-logo-mark-slack">
        <i /><i /><i /><i />
      </span>
    );
  }

  if (kind === "chrome") {
    return <span aria-hidden="true" className="app-logo-mark app-logo-mark-chrome" />;
  }

  const glyphs: Partial<Record<AppLogoKind, string>> = {
    codex: "✦",
    cursor: "◢",
    dingtalk: "⌁",
    github: "⌘",
    more: "+",
    notion: "N",
    vscode: "⌁",
  };

  return (
    <span
      aria-hidden="true"
      className={`app-logo-mark app-logo-mark-${kind}`}
    >
      {glyphs[kind] ?? kind.slice(0, 1).toUpperCase()}
    </span>
  );
}

function LogoSet({
  hidden = false,
  items,
  label,
}: {
  hidden?: boolean;
  items: readonly AppLogoItem[];
  label?: string;
}) {
  return (
    <ul
      aria-hidden={hidden || undefined}
      aria-label={hidden ? undefined : label}
      className="app-logo-set"
    >
      {items.map((item) => (
        <li
          aria-label={hidden ? undefined : item.name}
          className={`app-logo-item app-logo-item-${item.kind}`}
          key={`${hidden ? "duplicate" : "primary"}-${item.kind}-${item.name}`}
        >
          {item.src ? (
            <img
              alt={item.alt ?? item.name}
              className={`app-logo-image app-logo-image-${item.kind}`}
              src={item.src}
            />
          ) : (
            <AppLogoMark kind={item.kind} />
          )}
          <strong>{item.name}</strong>
        </li>
      ))}
    </ul>
  );
}

export function AppLogoLoop({ rows }: AppLogoLoopProps) {
  return (
    <div className="app-logo-loop">
      {rows.map((items, index) => (
        <div
          className={`app-logo-row${index % 2 === 1 ? " app-logo-row-reverse" : ""}`}
          key={`logo-row-${index}`}
        >
          <div className="app-logo-track">
            <LogoSet items={items} label={`示例连接软件第 ${index + 1} 行`} />
            <LogoSet hidden items={items} />
          </div>
        </div>
      ))}
    </div>
  );
}
