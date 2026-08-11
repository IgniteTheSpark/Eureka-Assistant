from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Literal, Sequence
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
_CLOCK_NUMBER = r"(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})"
_CLOCK_PATTERN = re.compile(
    r"(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上|今晚|昨晚|夜里)?"
    rf"\s*({_CLOCK_NUMBER})\s*(?:[:：点时])\s*"
    rf"(?:({_CLOCK_NUMBER})\s*分?|半)?"
)
_RANGE_SEPARATOR = re.compile(r"(?:到|至|~|-|—|－)")
_DURATION_PATTERN = re.compile(
    rf"({_CLOCK_NUMBER})\s*(?:个)?(小时|分钟)"
)
_ALL_DAY_PATTERN = re.compile(r"(?:全天|一整天|整天)")
_MONTH_DAY_PATTERN = re.compile(r"(?<!\d)(\d{1,2})月(\d{1,2})日?")
_ISO_DATE_PATTERN = re.compile(r"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)")


ScheduleShape = Literal["point", "range", "duration", "all_day", "none"]


@dataclass(frozen=True)
class CaptureTemporalContext:
    anchor_date: date | None = None
    period: str | None = None


@dataclass(frozen=True)
class CaptureTemporalHints:
    anchor_date: date | None = None
    period: str | None = None
    occurred_at: datetime | None = None
    shape: ScheduleShape = "none"
    start_at: datetime | None = None
    end_at: datetime | None = None
    interval_candidates: tuple[tuple[datetime, datetime], ...] = ()


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


def _parse_clock_number(value: str) -> int | None:
    if value.isdigit():
        return int(value)
    normalized = value.replace("两", "二").replace("〇", "零")
    digits = {"零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
              "六": 6, "七": 7, "八": 8, "九": 9}
    if normalized == "十":
        return 10
    if "十" in normalized:
        left, right = normalized.split("十", 1)
        tens = digits.get(left, 1) if left else 1
        units = digits.get(right, 0) if right else 0
        return tens * 10 + units
    if len(normalized) == 1:
        return digits.get(normalized)
    return None


def _clock_parts(match: re.Match[str]) -> tuple[str | None, int, int] | None:
    hour = _parse_clock_number(match.group(2))
    minute_text = match.group(3)
    minute = (
        _parse_clock_number(minute_text)
        if minute_text
        else (30 if "半" in match.group(0) else 0)
    )
    if hour is None or minute is None or not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    marker = match.group(1)
    return (_resolve_period(marker or ""), hour, minute)


def _hour_candidates(hour: int, period: str | None) -> tuple[int, ...]:
    if period in {"下午", "晚上", "中午"}:
        return (hour + 12 if 1 <= hour <= 11 else hour,)
    if period == "凌晨":
        return (0 if hour == 12 else hour,)
    if period == "上午":
        return (hour,)
    if 1 <= hour <= 11:
        return (hour, hour + 12)
    return (hour,)


def _clock_candidates(
    match: re.Match[str],
    *,
    anchor_date: date,
    inherited_period: str | None,
) -> tuple[datetime, ...]:
    parts = _clock_parts(match)
    if parts is None:
        return ()
    marker, hour, minute = parts
    period = marker or inherited_period
    return tuple(
        datetime(
            anchor_date.year,
            anchor_date.month,
            anchor_date.day,
            candidate_hour,
            minute,
            tzinfo=_BEIJING,
        )
        for candidate_hour in _hour_candidates(hour, period)
        if 0 <= candidate_hour <= 23
    )


def _range_clock_matches(text: str) -> tuple[re.Match[str], re.Match[str]] | None:
    matches = list(_CLOCK_PATTERN.finditer(text))
    for start, end in zip(matches, matches[1:]):
        if _RANGE_SEPARATOR.search(text[start.end() : end.start()]):
            return start, end
    return None


def schedule_shape(source_text: str) -> ScheduleShape:
    text = (source_text or "").strip()
    if not text:
        return "none"
    if _ALL_DAY_PATTERN.search(text):
        return "all_day"
    if _range_clock_matches(text) is not None:
        return "range"
    if _CLOCK_PATTERN.search(text) and _DURATION_PATTERN.search(text):
        return "duration"
    if (
        _CLOCK_PATTERN.search(text)
        or _ISO_DATE_PATTERN.search(text)
        or _MONTH_DAY_PATTERN.search(text)
        or any(keyword in text for keyword, _ in _RELATIVE_DAYS)
        or _resolve_period(text)
    ):
        return "point"
    return "none"


def _intervals_for_range(
    start_match: re.Match[str],
    end_match: re.Match[str],
    *,
    anchor_date: date,
    inherited_period: str | None,
) -> tuple[tuple[datetime, datetime], ...]:
    start_parts = _clock_parts(start_match)
    end_parts = _clock_parts(end_match)
    if start_parts is None or end_parts is None:
        return ()
    start_marker, _, _ = start_parts
    end_marker, _, _ = end_parts
    effective_period = start_marker or inherited_period
    starts = _clock_candidates(
        start_match,
        anchor_date=anchor_date,
        inherited_period=effective_period,
    )
    ends = _clock_candidates(
        end_match,
        anchor_date=anchor_date,
        inherited_period=end_marker or effective_period,
    )
    intervals = {
        (start, end)
        for start in starts
        for end in ends
        if end > start and end - start <= timedelta(hours=12)
    }
    return tuple(sorted(intervals, key=lambda item: item[0]))


def _last_explicit_period(text: str) -> str | None:
    latest: tuple[int, str] | None = None
    for keyword, period in _PERIOD_KEYWORDS:
        position = text.rfind(keyword)
        if position >= 0 and (latest is None or position > latest[0]):
            latest = (position, period)
    return latest[1] if latest is not None else None


def _last_explicit_date(text: str, reference: datetime) -> date | None:
    candidates: list[tuple[int, date]] = []
    for keyword, delta in _RELATIVE_DAYS:
        for match in re.finditer(re.escape(keyword), text):
            candidates.append((match.start(), (reference + timedelta(days=delta)).date()))
    for match in _ISO_DATE_PATTERN.finditer(text):
        try:
            candidates.append((match.start(), date(*(int(value) for value in match.groups()))))
        except ValueError:
            continue
    for match in _MONTH_DAY_PATTERN.finditer(text):
        month, day = (int(value) for value in match.groups())
        try:
            candidates.append((match.start(), date(reference.year, month, day)))
        except ValueError:
            continue
    return max(candidates, default=(-1, None), key=lambda item: item[0])[1]


def temporal_contexts_for_intents(
    transcript: str,
    source_texts: Sequence[str],
    reference_datetime: datetime,
) -> tuple[CaptureTemporalContext, ...]:
    reference = _aware_reference(reference_datetime)
    cursor = 0
    anchor_date: date | None = None
    period: str | None = None
    contexts: list[CaptureTemporalContext] = []
    for source_text in source_texts:
        source = (source_text or "").strip()
        position = transcript.find(source, cursor) if source else -1
        if position < 0 and source:
            position = transcript.find(source)
        if position >= 0:
            cursor = position + len(source)
            relevant = transcript[:cursor]
        else:
            relevant = source
        anchor_date = _last_explicit_date(relevant, reference) or anchor_date
        period = _last_explicit_period(relevant) or period
        contexts.append(CaptureTemporalContext(anchor_date=anchor_date, period=period))
    return tuple(contexts)


def extract_temporal_hints(
    source_text: str,
    reference_datetime: datetime,
    *,
    inherited_period: str | None = None,
    inherited_date: date | None = None,
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
    if not has_explicit_date and inherited_date is not None:
        anchor_date = inherited_date
    period = _resolve_period(text) or inherited_period
    shape = schedule_shape(text)

    if shape == "all_day":
        start = datetime(
            anchor_date.year,
            anchor_date.month,
            anchor_date.day,
            tzinfo=_BEIJING,
        )
        return CaptureTemporalHints(
            anchor_date=anchor_date,
            period=period,
            shape=shape,
            start_at=start,
            end_at=start + timedelta(days=1),
            interval_candidates=((start, start + timedelta(days=1)),),
        )

    range_matches = _range_clock_matches(text)
    if shape == "range" and range_matches is not None:
        intervals = _intervals_for_range(
            *range_matches,
            anchor_date=anchor_date,
            inherited_period=period,
        )
        resolved = intervals[0] if len(intervals) == 1 else None
        return CaptureTemporalHints(
            anchor_date=anchor_date,
            period=period,
            occurred_at=resolved[0] if resolved else None,
            shape=shape,
            start_at=resolved[0] if resolved else None,
            end_at=resolved[1] if resolved else None,
            interval_candidates=intervals,
        )

    clock_match = _CLOCK_PATTERN.search(text)
    if clock_match:
        candidates = _clock_candidates(
            clock_match,
            anchor_date=anchor_date,
            inherited_period=period,
        )
        if shape == "duration" and candidates:
            duration_match = _DURATION_PATTERN.search(text, clock_match.end())
            if duration_match is not None:
                amount = _parse_clock_number(duration_match.group(1))
                if amount is not None and amount > 0:
                    duration = timedelta(
                        hours=amount
                        if duration_match.group(2) == "小时"
                        else 0,
                        minutes=amount
                        if duration_match.group(2) == "分钟"
                        else 0,
                    )
                    intervals = tuple((start, start + duration) for start in candidates)
                    resolved = intervals[0] if len(intervals) == 1 else None
                    return CaptureTemporalHints(
                        anchor_date=anchor_date,
                        period=period,
                        occurred_at=resolved[0] if resolved else None,
                        shape=shape,
                        start_at=resolved[0] if resolved else None,
                        end_at=resolved[1] if resolved else None,
                        interval_candidates=intervals,
                    )
        if candidates:
            occurred_at = min(
                candidates,
                key=lambda candidate: abs((candidate - reference).total_seconds()),
            )
            return CaptureTemporalHints(
                anchor_date=anchor_date,
                period=period,
                occurred_at=occurred_at,
                shape=shape,
                start_at=occurred_at,
            )

    if any(keyword in text for keyword in ("刚刚", "刚才", "现在", "这会儿")):
        return CaptureTemporalHints(
            anchor_date=reference.date(),
            period=period,
            occurred_at=reference_datetime,
            shape="point",
        )

    if has_explicit_date or inherited_date is not None or period:
        return CaptureTemporalHints(
            anchor_date=anchor_date,
            period=period,
            shape=shape,
        )
    return CaptureTemporalHints()


def canonical_asset_temporal_values(
    source_text: str,
    reference_datetime: datetime,
    *,
    inherited_period: str | None = None,
    inherited_date: date | None = None,
) -> tuple[CaptureTemporalHints, str | None, datetime | None, datetime | None]:
    """Return transcript-grounded asset time fields in storage precedence order.

    A capture transcript is the authority for semantic time. The model may
    propose temporal arguments, but callers use this result whenever a trusted
    capture reference and its atomic source text are available.
    """
    hints = extract_temporal_hints(
        source_text,
        reference_datetime,
        inherited_period=inherited_period,
        inherited_date=inherited_date,
    )
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
