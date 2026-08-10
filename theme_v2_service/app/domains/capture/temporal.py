from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo


_BEIJING = ZoneInfo("Asia/Shanghai")
_PERIOD_KEYWORDS: tuple[tuple[str, str], ...] = (
    ("凌晨", "凌晨"),
    ("清晨", "上午"),
    ("早上", "上午"),
    ("上午", "上午"),
    ("中午", "中午"),
    ("下午", "下午"),
    ("傍晚", "晚上"),
    ("晚上", "晚上"),
    ("今晚", "晚上"),
    ("昨晚", "晚上"),
    ("夜里", "晚上"),
)
_RELATIVE_DAYS: tuple[tuple[str, int], ...] = (
    ("大前天", -3),
    ("前天", -2),
    ("昨天", -1),
    ("昨日", -1),
    ("昨晚", -1),
    ("今天", 0),
    ("今日", 0),
    ("明天", 1),
    ("后天", 2),
)
_CLOCK_PATTERN = re.compile(
    r"(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上|今晚|昨晚|夜里)?"
    r"\s*(\d{1,2})\s*(?:[:：点时])\s*(?:(\d{1,2})\s*分?|半)?"
)
_MONTH_DAY_PATTERN = re.compile(r"(?<!\d)(\d{1,2})月(\d{1,2})日?")
_ISO_DATE_PATTERN = re.compile(r"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)")


@dataclass(frozen=True)
class CaptureTemporalHints:
    anchor_date: date | None = None
    period: str | None = None
    occurred_at: datetime | None = None


def _aware_reference(reference_datetime: datetime) -> datetime:
    aware = reference_datetime
    if aware.tzinfo is None:
        aware = aware.replace(tzinfo=timezone.utc)
    return aware.astimezone(_BEIJING)


def _resolve_date(text: str, reference: datetime) -> tuple[date, bool]:
    for keyword, delta in _RELATIVE_DAYS:
        if keyword in text:
            return (reference + timedelta(days=delta)).date(), True

    iso_match = _ISO_DATE_PATTERN.search(text)
    if iso_match:
        try:
            return date(*(int(value) for value in iso_match.groups())), True
        except ValueError:
            pass

    month_day_match = _MONTH_DAY_PATTERN.search(text)
    if month_day_match:
        month, day = (int(value) for value in month_day_match.groups())
        try:
            return date(reference.year, month, day), True
        except ValueError:
            pass
    return reference.date(), False


def _resolve_period(text: str) -> str | None:
    for keyword, period in _PERIOD_KEYWORDS:
        if keyword in text:
            return period
    return None


def extract_temporal_hints(
    source_text: str,
    reference_datetime: datetime,
) -> CaptureTemporalHints:
    """Extract only explicit time facts without inventing a clock.

    The reference is the capture timestamp, not the time a background worker
    happens to process the recording.
    """
    text = (source_text or "").strip()
    if not text:
        return CaptureTemporalHints()
    reference = _aware_reference(reference_datetime)
    anchor_date, has_explicit_date = _resolve_date(text, reference)
    period = _resolve_period(text)

    clock_match = _CLOCK_PATTERN.search(text)
    if clock_match:
        marker = clock_match.group(1) or ""
        hour = int(clock_match.group(2))
        minute_text = clock_match.group(3)
        minute = int(minute_text) if minute_text else (30 if "半" in clock_match.group(0) else 0)
        if marker in {"下午", "傍晚", "晚上", "今晚", "昨晚", "夜里"} and 1 <= hour <= 11:
            hour += 12
        elif marker == "凌晨" and hour == 12:
            hour = 0
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            occurred_at = datetime(
                anchor_date.year,
                anchor_date.month,
                anchor_date.day,
                hour,
                minute,
                tzinfo=_BEIJING,
            )
            return CaptureTemporalHints(
                anchor_date=anchor_date,
                period=period,
                occurred_at=occurred_at,
            )

    if any(keyword in text for keyword in ("刚刚", "刚才", "现在", "这会儿")):
        return CaptureTemporalHints(
            anchor_date=reference.date(),
            period=period,
            occurred_at=reference_datetime,
        )

    if has_explicit_date or period:
        return CaptureTemporalHints(anchor_date=anchor_date, period=period)
    return CaptureTemporalHints()


def canonical_asset_temporal_values(
    source_text: str,
    reference_datetime: datetime,
) -> tuple[CaptureTemporalHints, str | None, datetime | None, datetime | None]:
    """Return transcript-grounded asset time fields in storage precedence order.

    A capture transcript is the authority for semantic time. The model may
    propose temporal arguments, but callers use this result whenever a trusted
    capture reference and its atomic source text are available.
    """
    hints = extract_temporal_hints(source_text, reference_datetime)
    if hints.occurred_at is not None:
        return hints, hints.period, hints.occurred_at, None
    if hints.anchor_date is not None:
        effective_at = datetime(
            hints.anchor_date.year,
            hints.anchor_date.month,
            hints.anchor_date.day,
            tzinfo=_BEIJING,
        )
        return hints, hints.period, None, effective_at
    return hints, None, None, reference_datetime


def date_anchor_field(schema: dict) -> str | None:
    properties = schema.get("properties")
    if not isinstance(properties, dict):
        properties = {
            key: value
            for key, value in schema.items()
            if isinstance(value, dict) and not key.startswith("x-")
        }
    for preferred in ("date", "run_date", "due_date", "played_at"):
        definition = properties.get(preferred)
        if isinstance(definition, dict) and definition.get("type") == "string":
            return preferred
    for name, definition in properties.items():
        if isinstance(definition, dict) and definition.get("format") == "date":
            return name
    return None
