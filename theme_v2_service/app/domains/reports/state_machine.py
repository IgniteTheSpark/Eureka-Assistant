from datetime import datetime

from app.db.base import utc_now
from app.domains.reports.models import ReportGenerationRun


class InvalidRunTransition(Exception):
    pass


TERMINAL_STATES = {"completed", "cancelled", "expired"}
ALLOWED_TRANSITIONS = {
    "planning": {"awaiting_selection", "failed", "cancelled"},
    "awaiting_selection": {"planning", "generating", "cancelled", "expired"},
    "generating": {"illustration_pending", "completed", "failed", "cancelled"},
    "illustration_pending": {"completed"},
    "failed": {"planning", "generating", "cancelled"},
    "completed": set(),
    "cancelled": set(),
    "expired": set(),
}


def _require(run: ReportGenerationRun, target: str, *fields: str) -> None:
    for field in fields:
        if getattr(run, field, None) is None:
            raise InvalidRunTransition(f"{target} requires {field}")


def transition_run(
    run: ReportGenerationRun,
    target: str,
    *,
    now: datetime | None = None,
) -> ReportGenerationRun:
    if target not in ALLOWED_TRANSITIONS.get(run.state, set()):
        raise InvalidRunTransition(f"cannot transition {run.state} to {target}")

    if target == "awaiting_selection":
        _require(run, target, "pending_decision")
    elif target == "generating":
        _require(run, target, "execution_plan", "generation_job_id")
    elif target in {"illustration_pending", "completed"}:
        _require(run, target, "report_id", "completed_at")
    elif target == "failed":
        _require(
            run,
            target,
            "failure_stage",
            "error_code",
            "error_message",
            "retry_from",
        )

    changed_at = now or utc_now()
    run.state = target
    run.updated_at = changed_at
    if target == "cancelled" and run.cancelled_at is None:
        run.cancelled_at = changed_at
    if target == "expired" and run.expires_at is None:
        run.expires_at = changed_at
    return run
