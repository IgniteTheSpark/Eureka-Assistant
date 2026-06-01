import { useState } from "react";

import { applyFormat } from "@/lib/format";
import type { FieldFormat } from "@/lib/render-spec";

/**
 * GenericField — renders one (label, value) pair from a payload using an
 * optional `format` directive. Used by AssetDetailDrawer to show the full
 * payload after the user opens a card.
 *
 * Keeps the same format vocabulary as SkillCard so display is consistent
 * between the compact card view and the expanded detail panel.
 */

interface GenericFieldProps {
  label: string;
  value: unknown;
  format?: FieldFormat;
  /** For long-form fields like content / description / markdown */
  multiline?: boolean;
}

// Beyond this many chars a multiline value is clamped with a 展开/收起 toggle so
// a long note doesn't swallow the whole drawer.
const CLAMP_THRESHOLD = 140;

export function GenericField({ label, value, format, multiline }: GenericFieldProps) {
  const display = applyFormat(value, format);
  const [expanded, setExpanded] = useState(false);
  if (!display) return null;

  const clampable = multiline && display.length > CLAMP_THRESHOLD;

  return (
    <div className="flex flex-col gap-1">
      <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
        {label}
      </div>
      <div
        className={[
          "text-eu-base text-eu-text-hi",
          multiline ? "whitespace-pre-wrap leading-relaxed" : "truncate",
          clampable && !expanded ? "line-clamp-4" : "",
        ].join(" ")}
      >
        {display}
      </div>
      {clampable && (
        <button
          type="button"
          onClick={() => setExpanded((e) => !e)}
          className="self-start text-eu-xs text-eu-accent-blue-fg hover:brightness-110 mt-0.5"
        >
          {expanded ? "收起" : "展开"}
        </button>
      )}
    </div>
  );
}
