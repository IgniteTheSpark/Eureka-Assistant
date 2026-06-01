import { useState } from "react";
import { Smartphone } from "lucide-react";

/**
 * DeviceMenu — TopBar icon → popover.
 *
 * M0: placeholder. Shows "未连接 — 设备配对功能即将上线".
 * Real device pairing (hardware voice device discovery / BLE handshake) is
 * post-MVP product work.
 */
export function DeviceMenu() {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button
        type="button"
        aria-label="设备连接"
        onClick={() => setOpen((v) => !v)}
        className="p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover transition-colors duration-eu-fast"
      >
        <Smartphone size={18} strokeWidth={1.75} />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div
            className={[
              "absolute right-0 top-full mt-2 z-50",
              "w-64 p-eu-md rounded-eu-md",
              "bg-eu-surface-raised border border-eu-border shadow-eu-md",
              "text-eu-sm",
            ].join(" ")}
          >
            <div className="text-eu-text-hi font-medium mb-1">未连接</div>
            <div className="text-eu-text-mid">设备配对功能即将上线。</div>
          </div>
        </>
      )}
    </div>
  );
}
