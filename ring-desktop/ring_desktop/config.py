import json
import os
from typing import Optional

from .vibration import VibrationType


def load_config(path: str) -> dict:
    """读配置；文件不存在则返回 {"default": {}}。"""
    if not os.path.exists(path):
        return {"default": {}}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_config(path: str, cfg: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def resolve_action(cfg: dict, bundle_id: Optional[str], gesture_name: str) -> Optional[dict]:
    """先查该 app 的档；该手势没配则回落到 default；都没有返回 None。"""
    app_profile = cfg.get(bundle_id or "", {})
    if gesture_name in app_profile:
        return app_profile[gesture_name]
    return cfg.get("default", {}).get(gesture_name)


def resolve_vibration(
    cfg: dict,
    bundle_id: Optional[str],
    event_name: str,
) -> Optional[VibrationType]:
    """Resolve an event's vibration mode, honoring an explicit app-level off."""
    app_events = cfg.get(bundle_id or "", {}).get("vibration", {})
    if event_name in app_events:
        value = app_events[event_name]
    else:
        value = cfg.get("default", {}).get("vibration", {}).get(event_name)
    if value in (None, "", "off"):
        return None
    try:
        return VibrationType(value)
    except ValueError:
        return None
