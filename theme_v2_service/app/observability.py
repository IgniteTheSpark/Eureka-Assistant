from __future__ import annotations

from collections import defaultdict
from threading import Lock
from typing import Mapping


REPORT_METRICS = (
    "planner_duration_ms",
    "planner_tokens",
    "planner_failed_total",
    "planner_clarification_rate",
    "planner_option_count",
    "related_skill_discovery_rate",
    "pipeline_duration_ms",
    "pipeline_success_rate",
    "failure_stage",
    "web_search_count",
    "web_search_degraded_total",
    "image_generation_count",
    "image_degraded_total",
    "render_duration_ms",
    "tokens_used",
    "run_created_total",
    "run_awaiting_selection_total",
    "run_completed_total",
    "run_failed_total",
    "run_cancelled_total",
    "run_expired_total",
    "job_retry_total",
    "job_lease_recovered_total",
    "share_created_total",
    "share_opened_total",
    "share_revoked_total",
    "share_expired_total",
    "invalid_share_token_total",
    "invalid_media_access_total",
    "share_card_generated_total",
)

SAFE_LOG_FIELDS = frozenset(
    {
        "run_id",
        "job_id",
        "report_id",
        "share_id",
        "trace_id",
        "stage",
        "failure_stage",
        "state",
        "status",
        "error_code",
        "job_type",
        "attempt",
    }
)


def sanitize_log_context(**context: object) -> dict[str, object]:
    return {
        key: value
        for key, value in context.items()
        if key in SAFE_LOG_FIELDS and value is not None
    }


def _label_key(labels: Mapping[str, str] | None) -> tuple[tuple[str, str], ...]:
    return tuple(sorted((labels or {}).items()))


def _number(value: float) -> str:
    return str(int(value)) if value.is_integer() else format(value, ".12g")


class MetricRegistry:
    """Small process-local registry for the isolated Theme V2 runtime."""

    def __init__(self) -> None:
        self._values: dict[tuple[str, tuple[tuple[str, str], ...]], float] = (
            defaultdict(float)
        )
        self._lock = Lock()

    def increment(
        self,
        name: str,
        value: float = 1,
        *,
        labels: Mapping[str, str] | None = None,
    ) -> None:
        self._validate(name, value)
        with self._lock:
            self._values[(name, _label_key(labels))] += value

    def observe(
        self,
        name: str,
        value: float,
        *,
        labels: Mapping[str, str] | None = None,
    ) -> None:
        self._validate(name, value)
        with self._lock:
            self._values[(name, _label_key(labels))] = value

    def value(
        self,
        name: str,
        *,
        labels: Mapping[str, str] | None = None,
    ) -> float:
        with self._lock:
            return self._values.get((name, _label_key(labels)), 0.0)

    def render_prometheus(self) -> str:
        with self._lock:
            values = dict(self._values)
        lines = []
        for name in REPORT_METRICS:
            entries = sorted(
                (
                    (labels, value)
                    for (metric_name, labels), value in values.items()
                    if metric_name == name
                ),
                key=lambda item: item[0],
            )
            if not entries:
                entries = [((), 0.0)]
            for labels, value in entries:
                suffix = ""
                if labels:
                    rendered = ",".join(
                        f'{key}="{label.replace(chr(34), chr(92) + chr(34))}"'
                        for key, label in labels
                    )
                    suffix = f"{{{rendered}}}"
                lines.append(f"{name}{suffix} {_number(value)}")
        return "\n".join(lines) + "\n"

    @staticmethod
    def _validate(name: str, value: float) -> None:
        if name not in REPORT_METRICS:
            raise ValueError(f"unknown report metric: {name}")
        if value < 0:
            raise ValueError("metric value must be non-negative")


metrics = MetricRegistry()
