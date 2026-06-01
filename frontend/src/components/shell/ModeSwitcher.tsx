import { usePresentationMode } from "@/context/PresentationModeContext";
import type { PresentationMode } from "@/context/PresentationModeContext";

/**
 * ModeSwitcher — segmented control for switching between presentation modes.
 *
 * Driven by PresentationModeContext. Stored in localStorage; on auth swap, the
 * hook's implementation changes but this component's API stays stable.
 */

interface Option {
  value: PresentationMode;
  label: string;
  hint: string;
}

const OPTIONS: Option[] = [
  { value: "asset",    label: "资产模式", hint: "知识沉淀" },
  { value: "calendar", label: "日历模式", hint: "商务日程" },
];

export function ModeSwitcher() {
  const { mode, setMode } = usePresentationMode();

  return (
    <div className="grid grid-cols-2 gap-1.5 p-1 bg-eu-surface rounded-eu-md border border-eu-border">
      {OPTIONS.map((opt) => {
        const active = mode === opt.value;
        return (
          <button
            key={opt.value}
            type="button"
            onClick={() => setMode(opt.value)}
            className={[
              "flex flex-col items-start px-eu-sm py-1.5 rounded-eu-sm text-left",
              "transition-colors duration-eu-fast ease-eu-out",
              active
                ? "bg-eu-brand-faint text-eu-text-hi"
                : "text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover",
            ].join(" ")}
          >
            <span className="text-eu-sm font-medium">{opt.label}</span>
            <span className="text-eu-xs text-eu-text-lo">{opt.hint}</span>
          </button>
        );
      })}
    </div>
  );
}
