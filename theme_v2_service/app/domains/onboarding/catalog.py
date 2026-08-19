"""Onboarding curated category catalog (§6.2).

Versioned product configuration with stable category IDs. The first release is
a compact carousel; the four mandatory categories are present with exactly
three field suggestions each. The catalog loads without an LLM; clients bundle
this as a fallback when the catalog endpoint is temporarily unavailable.
"""
from __future__ import annotations

CATALOG_VERSION = "2026-08-v1"

# Stable category identity -> definition. Field order is the suggested order.
ONBOARDING_CATALOG: dict[str, dict] = {
    "running": {
        "label": "跑步",
        "description": "记录每次跑步的距离、时长与地点",
        "fields": [
            {"key": "distance_km", "label": "距离(公里)", "type": "number"},
            {"key": "duration_min", "label": "时长(分钟)", "type": "duration"},
            {"key": "location", "label": "地点", "type": "text"},
        ],
        "hint": "我今天沿着河边跑了 5 公里,用了 32 分钟。",
    },
    "drinking_water": {
        "label": "喝水",
        "description": "记录每天的饮水量与方式",
        "fields": [
            {"key": "amount_ml", "label": "水量(毫升)", "type": "number"},
            {"key": "time", "label": "时间", "type": "time"},
            {"key": "container", "label": "容器", "type": "text"},
        ],
        "hint": "下午我在办公室用保温杯喝了 500 毫升水。",
    },
    "baby_feeding": {
        "label": "宝宝喂养",
        "description": "记录宝宝每次喂养的方式与奶量",
        "fields": [
            {"key": "method", "label": "喂养方式", "type": "text"},
            {"key": "amount_ml", "label": "奶量(毫升)", "type": "number"},
            {"key": "time", "label": "时间", "type": "time"},
        ],
        "hint": "早上八点我用奶瓶喂了宝宝 120 毫升。",
    },
    "dancing": {
        "label": "跳舞",
        "description": "记录舞蹈练习的舞种与时长",
        "fields": [
            {"key": "style", "label": "舞种", "type": "text"},
            {"key": "studio", "label": "舞室", "type": "text"},
            {"key": "duration_min", "label": "时长(分钟)", "type": "duration"},
        ],
        "hint": "今晚我在星梦舞蹈室练了 60 分钟嘻哈。",
    },
}

# Mandatory acceptance entries (§6.2 / §12.1).
REQUIRED_CATEGORIES = ("running", "drinking_water", "baby_feeding", "dancing")


def catalog_categories() -> list[dict]:
    return [dict(value, id=category) for category, value in ONBOARDING_CATALOG.items()]


def get_category(category_id: str) -> dict | None:
    value = ONBOARDING_CATALOG.get(category_id)
    if value is None:
        return None
    return dict(value, id=category_id)
