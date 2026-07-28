"""Authoritative effective-time rule shared by every asset read contract."""

from datetime import datetime, timedelta, timezone
from typing import Any, Optional


_BEIJING = timezone(timedelta(hours=8))


def parse_asset_time(value: Any) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not value or not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=_BEIJING)


def effective_at_for_asset(
    asset: Any,
    skill_name: str,
    render_spec: Optional[dict] = None,
) -> datetime:
    """Return when an asset is meaningful, never merely when it was serialized."""
    payload = asset.payload or {}
    if getattr(asset, "occurred_at", None):
        return asset.occurred_at
    spec = render_spec if isinstance(render_spec, dict) else {}
    anchor = spec.get("timeline_anchor")
    if anchor:
        anchored = parse_asset_time(payload.get(anchor))
        if anchored:
            return anchored
    if skill_name == "todo":
        return parse_asset_time(payload.get("due_date")) or asset.created_at
    if skill_name == "expense":
        return (
            parse_asset_time(payload.get("at"))
            or parse_asset_time(payload.get("date"))
            or asset.created_at
        )
    return asset.created_at
