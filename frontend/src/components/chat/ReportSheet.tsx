import { X } from "lucide-react";

import { useModalMount } from "@/context/ModalContext";

/**
 * ReportSheet — full-screen viewer for an agent-generated HTML report.
 *
 * The report is the html-summary feature's output surface. It renders the
 * raw HTML inside a SANDBOXED iframe via `srcDoc`:
 *
 *   - `srcDoc` takes the HTML as a string — no URL, no temp domain, no
 *     server endpoint. The browser renders it inline.
 *   - `sandbox=""` (empty) gives the iframe a unique opaque origin and
 *     blocks scripts, forms, popups, top-navigation, and any access to the
 *     parent app's cookies / localStorage / DOM. So even a malicious /
 *     buggy LLM-generated document is inert — it can only draw.
 *     (Flip to `sandbox="allow-scripts"` later if we want interactive
 *     charts; the opaque origin still walls it off from the app.)
 *
 * Fills the whole PhoneFrame. Header with the title + ✕; the iframe owns
 * the rest. Mobile is the only target, so there's no desktop variant.
 */

interface ReportSheetProps {
  title: string;
  html: string;
  onClose: () => void;
}

export function ReportSheet({ title, html, onClose }: ReportSheetProps) {
  // Full-screen takeover — hide the dock while open (it's a page-like modal,
  // but a picker-style one: we want the dock gone, not floating over it).
  useModalMount();

  return (
    <div className="fixed inset-0 z-[60] flex flex-col bg-eu-bg eu-fade-in">
      {/* Header */}
      <header
        className="shrink-0 flex items-center gap-eu-sm px-eu-md py-eu-sm border-b border-eu-rule"
        style={{ background: "rgba(6,7,13,0.92)", backdropFilter: "blur(8px)" }}
      >
        <span className="text-eu-base">📊</span>
        <div className="flex-1 min-w-0 text-eu-base text-eu-text-hi font-medium truncate">
          {title || "报告"}
        </div>
        <button
          type="button"
          aria-label="关闭"
          onClick={onClose}
          className="shrink-0 p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover active:scale-95"
        >
          <X size={18} strokeWidth={1.75} />
        </button>
      </header>

      {/* The report itself — sandboxed, no scripts, no parent access. */}
      <iframe
        title={title || "报告"}
        srcDoc={html}
        sandbox=""
        className="flex-1 w-full border-0 bg-white"
      />
    </div>
  );
}
