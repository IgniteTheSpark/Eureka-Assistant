import { useLocation } from "react-router-dom";

import { DeviceMenu } from "./DeviceMenu";
import { ProfileMenu } from "./ProfileMenu";
import { NotificationBell } from "./NotificationBell";

const PAGE_TITLES: Record<string, string> = {
  "/chat":          "对话",
  "/calendar":      "日历",
  "/library":       "资产库",
  "/notifications": "通知",
};

export function TopBar() {
  const { pathname } = useLocation();
  const title = PAGE_TITLES[pathname] ?? "Eureka";

  return (
    <header className="sticky top-0 z-30 pt-safe bg-eu-bg/85 backdrop-blur border-b border-eu-rule">
      <div className="h-12 px-eu-md flex items-center gap-eu-md">
        {/* Brand: SVG mark + wordmark; collapses to mark only on small screens */}
        <a href="/" className="flex items-center gap-eu-sm shrink-0" aria-label="Eureka home">
          <img src="/eureka.svg" alt="" className="h-6 w-6" />
          <span className="font-display text-eu-lg text-eu-text-hi tracking-tight hidden sm:inline">
            Eureka
          </span>
        </a>

        {/* Page title — center, ellipsis on overflow */}
        <h1 className="flex-1 text-center font-medium text-eu-md text-eu-text-hi truncate">
          {title}
        </h1>

        {/* Right cluster: 3 icon menus */}
        <div className="flex items-center gap-eu-xs shrink-0">
          <DeviceMenu />
          <NotificationBell />
          <ProfileMenu />
        </div>
      </div>
    </header>
  );
}
