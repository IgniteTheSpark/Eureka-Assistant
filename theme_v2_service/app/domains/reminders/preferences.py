from __future__ import annotations


DEFAULT_REMINDER_OFFSETS_MINUTES = (15,)


def normalize_reminder_offsets(
    value: object,
    *,
    missing_uses_default: bool = False,
) -> list[int]:
    if value is None:
        return list(DEFAULT_REMINDER_OFFSETS_MINUTES) if missing_uses_default else []
    if not isinstance(value, list):
        raise ValueError("reminder offsets must be a list of non-negative integers")
    if any(
        not isinstance(offset, int) or isinstance(offset, bool) or offset < 0
        for offset in value
    ):
        raise ValueError("reminder offsets must be non-negative integers")
    return sorted(set(value))
