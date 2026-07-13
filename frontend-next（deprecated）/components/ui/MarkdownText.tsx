"use client";

/**
 * Lightweight markdown renderer — handles the subset Claude typically outputs:
 * **bold**, *italic*, `code`, ## headings, - bullet lists, numbered lists,
 * blank-line paragraph breaks, | table rows |.
 * No external dependency.
 */

interface Props {
  text: string;
  style?: React.CSSProperties;
}

type Block =
  | { kind: "heading"; level: number; text: string }
  | { kind: "bullet"; items: string[] }
  | { kind: "ordered"; items: string[] }
  | { kind: "table"; rows: string[][] }
  | { kind: "code"; text: string }
  | { kind: "para"; text: string }
  | { kind: "hr" };

function parseInline(raw: string): React.ReactNode {
  // Split on **bold**, *italic*, `code`
  const parts: React.ReactNode[] = [];
  const re = /(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let key = 0;
  while ((m = re.exec(raw)) !== null) {
    if (m.index > last) parts.push(raw.slice(last, m.index));
    if (m[2] !== undefined) {
      parts.push(<strong key={key++}>{m[2]}</strong>);
    } else if (m[3] !== undefined) {
      parts.push(<em key={key++}>{m[3]}</em>);
    } else if (m[4] !== undefined) {
      parts.push(
        <code
          key={key++}
          style={{
            fontFamily: "monospace",
            fontSize: "0.88em",
            background: "rgba(15,23,42,.06)",
            borderRadius: "4px",
            padding: "1px 5px",
            color: "var(--blue)",
          }}
        >
          {m[4]}
        </code>
      );
    }
    last = m.index + m[0].length;
  }
  if (last < raw.length) parts.push(raw.slice(last));
  return parts.length === 1 ? parts[0] : <>{parts}</>;
}

function parseBlocks(text: string): Block[] {
  const blocks: Block[] = [];
  const lines = text.split("\n");
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code block
    if (line.startsWith("```")) {
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith("```")) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      blocks.push({ kind: "code", text: codeLines.join("\n") });
      continue;
    }

    // Heading
    const headingMatch = line.match(/^(#{1,3})\s+(.+)/);
    if (headingMatch) {
      blocks.push({ kind: "heading", level: headingMatch[1].length, text: headingMatch[2] });
      i++;
      continue;
    }

    // HR
    if (/^[-*]{3,}$/.test(line.trim())) {
      blocks.push({ kind: "hr" });
      i++;
      continue;
    }

    // Table row
    if (line.trim().startsWith("|") && line.trim().endsWith("|")) {
      const tableRows: string[][] = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        const row = lines[i].trim().slice(1, -1).split("|").map((c) => c.trim());
        // skip separator rows like |---|---|
        if (!row.every((c) => /^[-: ]+$/.test(c))) {
          tableRows.push(row);
        }
        i++;
      }
      if (tableRows.length > 0) blocks.push({ kind: "table", rows: tableRows });
      continue;
    }

    // Bullet list
    if (/^[-*•]\s/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^[-*•]\s/.test(lines[i])) {
        items.push(lines[i].replace(/^[-*•]\s+/, ""));
        i++;
      }
      blocks.push({ kind: "bullet", items });
      continue;
    }

    // Ordered list
    if (/^\d+\.\s/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\d+\.\s/.test(lines[i])) {
        items.push(lines[i].replace(/^\d+\.\s+/, ""));
        i++;
      }
      blocks.push({ kind: "ordered", items });
      continue;
    }

    // Blank line
    if (line.trim() === "") {
      i++;
      continue;
    }

    // Paragraph: accumulate consecutive non-special lines
    const paraLines: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !/^(#{1,3}\s|[-*•]\s|\d+\.\s|```)/.test(lines[i]) &&
      !(lines[i].trim().startsWith("|") && lines[i].trim().endsWith("|")) &&
      !/^[-*]{3,}$/.test(lines[i].trim())
    ) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      blocks.push({ kind: "para", text: paraLines.join("\n") });
    }
  }
  return blocks;
}

export default function MarkdownText({ text, style }: Props) {
  const blocks = parseBlocks(text);

  return (
    <div style={{ fontSize: "13px", lineHeight: 1.7, color: "var(--text)", ...style }}>
      {blocks.map((block, bi) => {
        switch (block.kind) {
          case "heading": {
            const sizes = ["16px", "14px", "13px"];
            return (
              <div
                key={bi}
                style={{
                  fontWeight: 700,
                  fontSize: sizes[block.level - 1] ?? "13px",
                  color: "var(--text)",
                  marginTop: bi > 0 ? "10px" : "0",
                  marginBottom: "4px",
                }}
              >
                {parseInline(block.text)}
              </div>
            );
          }

          case "bullet":
            return (
              <ul
                key={bi}
                style={{
                  margin: "4px 0",
                  paddingLeft: "18px",
                  display: "flex",
                  flexDirection: "column",
                  gap: "2px",
                }}
              >
                {block.items.map((item, ii) => (
                  <li key={ii} style={{ listStyleType: "disc" }}>
                    {parseInline(item)}
                  </li>
                ))}
              </ul>
            );

          case "ordered":
            return (
              <ol
                key={bi}
                style={{
                  margin: "4px 0",
                  paddingLeft: "18px",
                  display: "flex",
                  flexDirection: "column",
                  gap: "2px",
                }}
              >
                {block.items.map((item, ii) => (
                  <li key={ii} style={{ listStyleType: "decimal" }}>
                    {parseInline(item)}
                  </li>
                ))}
              </ol>
            );

          case "code":
            return (
              <pre
                key={bi}
                style={{
                  background: "rgba(15,23,42,.05)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--rs)",
                  padding: "8px 10px",
                  fontSize: "11px",
                  fontFamily: "monospace",
                  overflowX: "auto",
                  margin: "4px 0",
                  whiteSpace: "pre-wrap",
                  wordBreak: "break-all",
                }}
              >
                {block.text}
              </pre>
            );

          case "table":
            return (
              <div key={bi} style={{ overflowX: "auto", margin: "4px 0" }}>
                <table
                  style={{
                    borderCollapse: "collapse",
                    width: "100%",
                    fontSize: "12px",
                  }}
                >
                  <tbody>
                    {block.rows.map((row, ri) => (
                      <tr
                        key={ri}
                        style={{
                          background: ri === 0 ? "var(--surface2)" : "transparent",
                          borderBottom: "1px solid var(--border)",
                        }}
                      >
                        {row.map((cell, ci) => (
                          <td
                            key={ci}
                            style={{
                              padding: "4px 8px",
                              fontWeight: ri === 0 ? 600 : 400,
                              color: ri === 0 ? "var(--text)" : "var(--text2)",
                              whiteSpace: "nowrap",
                            }}
                          >
                            {parseInline(cell)}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );

          case "hr":
            return (
              <hr
                key={bi}
                style={{ border: "none", borderTop: "1px solid var(--border)", margin: "8px 0" }}
              />
            );

          case "para":
          default: {
            // Split by newline for soft line breaks
            const lines = (block as { kind: "para"; text: string }).text.split("\n");
            return (
              <p key={bi} style={{ margin: "2px 0" }}>
                {lines.map((ln, li) => (
                  <span key={li}>
                    {parseInline(ln)}
                    {li < lines.length - 1 && <br />}
                  </span>
                ))}
              </p>
            );
          }
        }
      })}
    </div>
  );
}
