from typing import Optional, List, Dict

from AppKit import NSWorkspace


def frontmost_bundle_id() -> Optional[str]:
    """当前最前台 app 的 bundle id，如 'com.anthropic.claudefordesktop'。"""
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    return str(app.bundleIdentifier()) if app else None


def running_apps() -> List[Dict[str, str]]:
    """活跃(常规)运行中的 app 列表，供配置窗挑选。"""
    out = []
    for a in NSWorkspace.sharedWorkspace().runningApplications():
        if a.activationPolicy() == 0 and a.bundleIdentifier():  # 0 = regular
            out.append({"name": str(a.localizedName()), "bundle": str(a.bundleIdentifier())})
    seen, uniq = set(), []
    for x in sorted(out, key=lambda d: d["name"].lower()):
        if x["bundle"] not in seen:
            seen.add(x["bundle"])
            uniq.append(x)
    return uniq
