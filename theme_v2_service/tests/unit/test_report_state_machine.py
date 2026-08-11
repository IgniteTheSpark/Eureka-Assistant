from datetime import datetime

import pytest

from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import ReportPlanOption, ShareCardSpec
from app.domains.reports.state_machine import (
    InvalidRunTransition,
    transition_run,
)


NOW = datetime(2026, 7, 31, 10, 0, 0)


def _run(state: str) -> ReportGenerationRun:
    return ReportGenerationRun(
        user_id="user-1",
        origin="user_initiated",
        state=state,
        launch_context={},
        answers={},
        evidence_scope={},
        pending_decision={"type": "plan_selection", "recommended_option_id": "o1"},
        plan_options=[],
        execution_plan={"template_id": "general", "resolved_asset_ids": []},
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        generation_job_id="job-1",
        report_id="report-1",
        failure_stage="content_generation",
        error_code="provider_error",
        error_message="temporary failure",
        retry_from="content_generation",
        completed_at=NOW,
    )


@pytest.mark.parametrize(
    ("source", "target"),
    [
        ("planning", "awaiting_selection"),
        ("awaiting_selection", "planning"),
        ("awaiting_selection", "generating"),
        ("generating", "completed"),
        ("generating", "illustration_pending"),
        ("illustration_pending", "completed"),
        ("planning", "failed"),
        ("generating", "failed"),
        ("planning", "cancelled"),
        ("awaiting_selection", "expired"),
        ("failed", "planning"),
        ("failed", "generating"),
    ],
)
def test_allowed_transitions(source, target):
    run = _run(source)

    assert transition_run(run, target, now=NOW).state == target


@pytest.mark.parametrize(
    ("source", "target"),
    [
        ("completed", "generating"),
        ("cancelled", "planning"),
        ("expired", "generating"),
        ("planning", "completed"),
        ("planning", "generating"),
        ("generating", "planning"),
        ("illustration_pending", "generating"),
    ],
)
def test_forbidden_transitions(source, target):
    with pytest.raises(InvalidRunTransition):
        transition_run(_run(source), target, now=NOW)


@pytest.mark.parametrize(
    ("target", "missing_fields"),
    [
        ("awaiting_selection", ("pending_decision",)),
        ("generating", ("execution_plan", "generation_job_id")),
        ("completed", ("report_id", "completed_at")),
        ("illustration_pending", ("report_id", "completed_at")),
        (
            "failed",
            ("failure_stage", "error_code", "error_message", "retry_from"),
        ),
    ],
)
def test_target_state_requires_its_invariants(target, missing_fields):
    source = {
        "awaiting_selection": "planning",
        "generating": "awaiting_selection",
        "completed": "generating",
        "illustration_pending": "generating",
        "failed": "planning",
    }[target]
    for field in missing_fields:
        run = _run(source)
        setattr(run, field, None)
        with pytest.raises(InvalidRunTransition, match=field):
            transition_run(run, target, now=NOW)


def test_agent_produced_schemas_forbid_unknown_fields_and_extra_highlights():
    with pytest.raises(ValueError):
        ReportPlanOption(
            id="o1",
            recommended=True,
            title="Summary",
            summary="Summary",
            report_goal="Goal",
            template_id="general",
            template_version="1.0.0",
            base_family="theme_synthesis",
            evidence_scope={},
            field_bindings={},
            web_search={"policy": "none"},
            illustration={"policy": "none"},
            render_policy="report_html_v1",
            invented=True,
        )

    with pytest.raises(ValueError):
        ShareCardSpec(
            headline="Headline",
            summary="Summary",
            highlights=["1", "2", "3", "4"],
            time_range="July",
        )
