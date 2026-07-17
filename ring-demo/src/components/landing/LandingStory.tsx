import { LANDING_CONTENT } from "./landing-content";
import { AppLogoLoop, type AppLogoItem } from "./AppLogoLoop";
import { ScrollFloatText } from "./ScrollFloatText";
import { SystemFinale } from "./SystemFinale";

const VIBE_APP_ROWS = [
  [
    { kind: "codex", name: "Codex", src: "/logos/codex-logo.jpeg" },
    { kind: "claude", name: "Claude", src: "/logos/claude-logo.png" },
    { kind: "dingtalk", name: "钉钉", src: "/logos/dingding-logo.png" },
    { kind: "lark", name: "飞书", src: "/logos/lark-logo.png" },
    { kind: "vscode", name: "VS Code", src: "/logos/vscode-logo.jpeg" },
    { kind: "cursor", name: "Cursor", src: "/logos/cursor-logo.png" },
    { kind: "trae", name: "Trae", src: "/logos/trae-logo.png" },
    { kind: "eurekamind", name: "EurekaMind", src: "/logos/eurekamind-logo.png" },
  ],
  [
    { kind: "notion", name: "Notion", src: "/logos/notion-logo.png" },
    { kind: "slack", name: "Slack", src: "/logos/slack-logo.jpeg" },
    { kind: "wechat", name: "微信", src: "/logos/wechat-logo.png" },
    { kind: "telegram", name: "Telegram", src: "/logos/telegram-logo.png" },
    { kind: "wisenote", name: "Wisenote", src: "/logos/wisenote-logo.jpeg" },
    { kind: "chrome", name: "Chrome", src: "/logos/chrome logo.png" },
    { kind: "spotify", name: "Spotify", src: "/logos/spotify logo.png" },
    { kind: "netease", name: "网易云音乐", src: "/logos/netease-logo.jpeg" },
    { kind: "more", name: "and even more" },
  ],
] satisfies readonly (readonly AppLogoItem[])[];

const SENSE_CHANNELS = {
  feel: "反馈",
  speak: "语音",
  touch: "手势",
} as const;

export function LandingStory() {
  const { flash, vibe, senses } = LANDING_CONTENT;

  return (
    <div className="landing-story">
      <section
        aria-labelledby="landing-flash-title"
        className="landing-section landing-flash"
      >
        <div className="landing-mode-grid landing-mode-grid-flash">
          <div className="landing-section-copy landing-mode-title">
            <p className="landing-mode-name"><strong>Flash</strong> · 闪念模式</p>
            <ScrollFloatText id="landing-flash-title" text={flash.title} />
            <p>{flash.description}</p>
          </div>

          <div
            aria-hidden="true"
            className="landing-mode-ring-slot"
            data-ring-chapter="flash-intro"
          />

          <figure
            className="landing-scene landing-mode-scene landing-scene-flash"
            data-ring-chapter="flash-scene"
          >
            <img
              alt="驾驶途中用戒指捕捉闪念"
              decoding="async"
              loading="lazy"
              src="/scenes/flash-driving-clean.webp"
            />
            <figcaption>
              <strong>一句话，成为下一步。</strong>
              <span>在移动途中捕捉想法，Eureka 继续完成理解与整理。</span>
            </figcaption>
          </figure>

          <div className="flash-mode-detail landing-mode-detail">
            <ol
              aria-label="闪念处理链路"
              className="flash-pipeline landing-mode-detail"
            >
              {flash.pipeline.map((step, index) => (
                <li key={step}>
                  <span>{String(index + 1).padStart(2, "0")}</span>
                  <strong>{step}</strong>
                </li>
              ))}
            </ol>

            <div className="flash-example-stage">
              <header>
                <h3>一句话，落到该去的地方。</h3>
                <p>理解意图以后，结果会进入对应的资产，而不是停在一段录音里。</p>
              </header>
              <div className="flash-examples" aria-label="闪念示例">
                {flash.examples.map((example) => (
                  <article key={example.input}>
                    <p>“{example.input}”</p>
                    <span aria-hidden="true">→</span>
                    <strong>{example.output}</strong>
                  </article>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      <section
        aria-labelledby="landing-vibe-title"
        className="landing-section landing-vibe"
      >
        <div className="landing-mode-grid landing-mode-grid-vibe">
          <div
            aria-hidden="true"
            className="landing-mode-ring-slot"
            data-ring-chapter="vibe-intro"
          />

          <div className="landing-section-copy landing-mode-title">
            <p className="landing-mode-name"><strong>Vibe</strong> · 随声操控</p>
            <ScrollFloatText id="landing-vibe-title" text={vibe.title} />
            <p>{vibe.description}</p>
          </div>

          <div className="vibe-ecosystem landing-mode-detail">
            <div className="vibe-ecosystem-copy">
              <h3>声音可以抵达你正在使用的工具。</h3>
              <p>从开发、沟通到浏览，让输入留在当前工作流里。</p>
            </div>
            <AppLogoLoop rows={VIBE_APP_ROWS} />
            <p className="vibe-support-note">{vibe.supportNote}</p>
          </div>

          <figure
            className="landing-scene landing-mode-scene landing-scene-vibe"
            data-ring-chapter="vibe-scene"
          >
            <img
              alt="在 Codex 前用戒指发出指令"
              decoding="async"
              loading="lazy"
              src="/scenes/vibe-office-clean.webp"
            />
            <figcaption>
              <strong>声音，直接进入当前工作。</strong>
              <span>不切换屏幕，也不打断正在进行的任务。</span>
            </figcaption>
          </figure>
        </div>
        <div
          aria-hidden="true"
          className="vibe-exit-anchor"
          data-ring-chapter="vibe-exit"
        />
      </section>

      <section
        aria-labelledby="landing-senses-title"
        className="landing-section landing-senses"
      >
        <header>
          <ScrollFloatText id="landing-senses-title" text="说 · 触 · 感" />
          <p>表达、控制与反馈，被收进一枚始终在手边的戒指。</p>
        </header>

        <div className="sense-scenes">
          {senses.map((sense) => (
            <article
              className={`sense-scene sense-scene-${sense.id}`}
              data-ring-chapter={sense.id}
              key={sense.id}
            >
              <span>{SENSE_CHANNELS[sense.id]}</span>
              <h3>{sense.title}</h3>
              <strong>{sense.metric}</strong>
              <p>{sense.description}</p>
            </article>
          ))}
        </div>
      </section>

      <SystemFinale />
    </div>
  );
}
