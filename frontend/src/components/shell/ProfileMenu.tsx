import { useState } from "react";
import { User } from "lucide-react";

import { ModeSwitcher } from "./ModeSwitcher";

/**
 * ProfileMenu — TopBar icon → popover with PresentationMode toggle + settings.
 *
 * M0: contains ModeSwitcher (Asset ⇄ Calendar) + placeholder "设置" link.
 */
export function ProfileMenu() {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button
        type="button"
        aria-label="个人中心"
        onClick={() => setOpen((v) => !v)}
        className="p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover transition-colors duration-eu-fast"
      >
        <User size={18} strokeWidth={1.75} />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div
            className={[
              "absolute right-0 top-full mt-2 z-50",
              "w-64 rounded-eu-md",
              "bg-eu-surface-raised border border-eu-border shadow-eu-md",
              "overflow-hidden",
            ].join(" ")}
          >
            <div className="px-eu-md py-eu-sm text-eu-xs text-eu-text-lo uppercase tracking-eu-caps">
              呈现模式
            </div>
            <div className="px-eu-md pb-eu-md">
              <ModeSwitcher />
            </div>

            <div className="border-t border-eu-rule">
              <button
                type="button"
                disabled
                className="w-full text-left px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:bg-eu-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
              >
                设置(即将上线)
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
