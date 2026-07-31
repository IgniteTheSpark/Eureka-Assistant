from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from pydantic import ValidationError

from app.domains.reports.pipeline import STAGES
from app.domains.reports.planner import PlannerResult
from app.domains.reports.schemas import ShareCardSpec
from app.domains.reports.shares import hash_share_token, issue_share_token
from app.domains.reports.state_machine import InvalidRunTransition, transition_run
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.templates import TemplateRegistry
from app.observability import REPORT_METRICS, sanitize_log_context


TEMPLATE_ROOT = Path(__file__).resolve().parents[1] / "report-templates"


@dataclass(frozen=True)
class EvalScenario:
    name: str
    evaluate: Callable[[], bool]


def _run(state: str) -> ReportGenerationRun:
    return ReportGenerationRun(
        user_id="eval-user",
        origin="user_initiated",
        state=state,
        launch_context={},
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )


def _rejects_four_plans() -> bool:
    try:
        PlannerResult(options=[{}] * 4)
    except ValidationError:
        return True
    return False


def _rejects_four_highlights() -> bool:
    try:
        ShareCardSpec(
            headline="Report",
            summary="Summary",
            highlights=["1", "2", "3", "4"],
            time_range="July",
        )
    except ValidationError:
        return True
    return False


def _completed_is_immutable() -> bool:
    run = _run("completed")
    try:
        transition_run(run, "planning")
    except InvalidRunTransition:
        return True
    return False


def _awaiting_can_expire() -> bool:
    run = _run("awaiting_selection")
    transition_run(run, "expired")
    return run.state == "expired" and run.expires_at is not None


def _share_tokens_are_opaque_and_hashed() -> bool:
    token = issue_share_token()
    digest = hash_share_token(token)
    return token != digest and len(digest) == 64 and "/" not in token


def _logs_drop_private_inputs() -> bool:
    return sanitize_log_context(
        run_id="run-1",
        share_token="secret-token",
        asset_payload={"secret": True},
        prompt="private prompt",
    ) == {"run_id": "run-1"}


def _pipeline_is_checkpoint_complete() -> bool:
    return STAGES == (
        "load_evidence",
        "web_search",
        "content_generation",
        "chart_validation",
        "illustration",
        "html_render",
        "persist",
    )


def _templates_load_offline() -> bool:
    registry = TemplateRegistry.load(TEMPLATE_ROOT)
    expected = {
        "child_growth_review",
        "finance_review",
        "general_period_review",
        "idea_synthesis",
        "learning_review",
        "pre_event_briefing",
        "tennis_monthly_review",
        "work_monthly_review",
    }
    loaded = {package.manifest.id for package in registry.packages}
    return expected == loaded


def _required_metrics_are_declared() -> bool:
    return {
        "planner_duration_ms",
        "pipeline_duration_ms",
        "run_expired_total",
        "invalid_share_token_total",
        "share_card_generated_total",
    }.issubset(REPORT_METRICS)


SCENARIOS = (
    EvalScenario("planner limits options", _rejects_four_plans),
    EvalScenario("share card limits highlights", _rejects_four_highlights),
    EvalScenario("completed runs are immutable", _completed_is_immutable),
    EvalScenario("awaiting runs can expire", _awaiting_can_expire),
    EvalScenario("share tokens are opaque", _share_tokens_are_opaque_and_hashed),
    EvalScenario("logs omit private inputs", _logs_drop_private_inputs),
    EvalScenario("pipeline stages are checkpoint complete", _pipeline_is_checkpoint_complete),
    EvalScenario("template registry loads offline", _templates_load_offline),
    EvalScenario("report observability is declared", _required_metrics_are_declared),
)
