import { LANDING_CONTENT } from "./landing-content";
import { ScrollFloatText } from "./ScrollFloatText";

export function SystemFinale() {
  const { system } = LANDING_CONTENT;

  return (
    <section
      aria-labelledby="landing-system-title"
      className="landing-section landing-system-finale"
    >
      <div className="system-finale-sticky">
        <div className="system-finale-copy">
          <ScrollFloatText
            id="landing-system-title"
            lines={[
              { text: "不是把助手缩小 ·" },
              { text: "是让智能始终在手边" },
            ]}
            text={system.title}
          />
          <p>{system.description}</p>
        </div>

        <ol aria-label="Eureka Ring 系统闭环" className="system-drop-flow">
          {system.nodes.map((node, index) => (
            <li
              className={`system-drop-node system-drop-node-${node.id} system-drop-node-${index % 2 === 0 ? "left" : "right"}`}
              data-system-drop-step={index + 1}
              key={node.id}
            >
              <span>{String(index + 1).padStart(2, "0")}</span>
              <div>
                <strong>{node.label}</strong>
                <small>{node.detail}</small>
                <em className="system-drop-signal">{node.signal}</em>
              </div>
              <i aria-hidden="true" />
            </li>
          ))}
        </ol>
      </div>

      <i
        aria-hidden="true"
        className="system-ring-anchor system-ring-anchor-start"
        data-ring-chapter="system-start"
      />
      <i
        aria-hidden="true"
        className="system-ring-anchor system-ring-anchor-end"
        data-ring-chapter="system-end"
      />
    </section>
  );
}
