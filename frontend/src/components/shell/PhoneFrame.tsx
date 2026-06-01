import { type ReactNode } from "react";

/**
 * PhoneFrame — constrains the entire app to an iPhone-17 sized viewport.
 *
 * Why: per user dogfood request (RV6) — the app is designed mobile-first
 * for硬件 input scenarios, and seeing it stretched across a desktop
 * browser hides layout problems that real users will see. Forcing the
 * exact target viewport (iPhone 17 = 393 × 852 logical points) makes the
 * design decisions concrete and consistent.
 *
 * Behavior:
 *   - Outer viewport ≥ 393 wide: phone-shaped frame centered on dark bg
 *     (black backdrop + rounded bezel + drop shadow, like a stage prop).
 *   - Outer viewport < 393 wide: frame fills viewport, no bezel (native
 *     mobile experience).
 *
 * Position-related side effects:
 *   - AppShell uses h-full inside (it used h-dvh before; PhoneFrame
 *     supplies the explicit 852px height).
 *   - Any `fixed` children inside (modals, sheets, dock) position
 *     against the viewport, NOT the frame — that's a known limitation;
 *     overlays will visually escape the frame. To keep them inside,
 *     we'd need a containing context (transform / contain), but those
 *     break backdrop-blur. Leave fixed escaping for now; revisit if it
 *     bothers anyone.
 *
 * iPhone 17 (standard, not Pro Max): 393 × 852 logical points, 19.5:9
 * aspect, ~6.3" diagonal. Bezel corner radius ~54px (matches Apple HIG
 * "Display Layer Effective Radius").
 */

const PHONE_W = 393;
const PHONE_H = 852;

interface PhoneFrameProps {
  children: ReactNode;
}

export function PhoneFrame({ children }: PhoneFrameProps) {
  return (
    <div
      // Backdrop: dark, with a subtle radial brand glow so the frame
      // doesn't sit on plain black.
      className="min-h-dvh w-full flex items-center justify-center overflow-hidden"
      style={{
        background:
          "radial-gradient(900px 600px at 50% 30%, rgba(111,158,255,0.08), transparent 70%), #04050b",
      }}
    >
      {/* The phone-shaped viewport. On a viewport smaller than the frame,
          we degrade to "fills viewport" so phones still feel native.
          `transform: translateZ(0)` creates a CSS containing block so that
          `position: fixed` children (modals, dock, sheets) stay inside
          the frame instead of leaking to the browser viewport. */}
      <div
        className="relative bg-eu-bg overflow-hidden"
        style={{
          width:        `min(${PHONE_W}px, 100vw)`,
          height:       `min(${PHONE_H}px, 100dvh)`,
          transform:    "translateZ(0)",   // make this a containing block for fixed children
          // Rounded "iPhone bezel" — apply only when the frame fits without
          // touching the viewport edge (use clamp via CSS).
          borderRadius: "54px",
          boxShadow: [
            // Inner subtle edge to suggest a screen
            "inset 0 0 0 1px rgba(255,255,255,0.04)",
            // Outer "phone body" — looks like brushed bezel
            "0 0 0 10px #0e0f15",
            "0 0 0 12px #20232b",
            "0 20px 60px rgba(0,0,0,0.55)",
            "0 40px 120px rgba(111,158,255,0.05)",
          ].join(", "),
        }}
      >
        {children}
      </div>
    </div>
  );
}
