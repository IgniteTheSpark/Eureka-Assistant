from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class ActiveExecutionSnapshot:
    revision: int


@dataclass(frozen=True)
class ProactiveSnapshot:
    cycle_started_at: datetime
    new_asset_count: int
    active_execution: ActiveExecutionSnapshot | None
    last_notified_local_date: date | None
    dismissed_until: datetime | None = None
    proactive_suppressed_until: datetime | None = None
    new_asset_arrived: bool = True

    def cycle_age(self, now: datetime) -> timedelta:
        return _as_utc_naive(now) - _as_utc_naive(self.cycle_started_at)


@dataclass(frozen=True)
class ProactiveDecision:
    create_execution: bool
    append_asset: bool
    next_revision: int | None
    should_notify: bool
    notification_local_date: date | None


def _as_utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _is_future(value: datetime | None, now: datetime) -> bool:
    return value is not None and _as_utc_naive(now) < _as_utc_naive(value)


def decide_proactive_summary(
    snapshot: ProactiveSnapshot,
    *,
    now: datetime,
    timezone_name: str,
) -> ProactiveDecision:
    if not snapshot.new_asset_arrived:
        return ProactiveDecision(False, False, None, False, None)

    utc_now = _as_utc_naive(now)
    local_date = utc_now.replace(tzinfo=timezone.utc).astimezone(
        ZoneInfo(timezone_name)
    ).date()
    threshold_met = (
        snapshot.cycle_age(utc_now) >= timedelta(days=7)
        and snapshot.new_asset_count >= 7
    )

    if snapshot.active_execution is None:
        return ProactiveDecision(
            create_execution=threshold_met,
            append_asset=True,
            next_revision=1 if threshold_met else None,
            should_notify=threshold_met,
            notification_local_date=local_date if threshold_met else None,
        )

    blocked = _is_future(snapshot.dismissed_until, utc_now) or _is_future(
        snapshot.proactive_suppressed_until,
        utc_now,
    )
    should_notify = (
        not blocked and snapshot.last_notified_local_date != local_date
    )
    return ProactiveDecision(
        create_execution=False,
        append_asset=True,
        next_revision=snapshot.active_execution.revision + 1,
        should_notify=should_notify,
        notification_local_date=local_date if should_notify else None,
    )
