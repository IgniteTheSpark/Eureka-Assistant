import pytest
from pydantic import ValidationError

from app.domains.reports.pipeline import (
    STAGES,
    PipelineContext,
    PipelineWriteRejected,
    execute_report_job,
)


def _handlers(calls: list[str], *, fail_at: str | None = None):
    handlers = {}
    for stage in STAGES:
        async def handle(context, current=stage):
            calls.append(current)
            if current == fail_at:
                raise RuntimeError(f"crash:{current}")
            return {"stage": current}

        handlers[stage] = handle
    return handlers


def _context(
    *,
    calls: list[str],
    completed: list[str] | None = None,
    fail_at: str | None = None,
    reject_after: str | None = None,
):
    checkpoints = {stage: {"stage": stage} for stage in completed or []}

    async def assert_current():
        return None

    async def save(stage, result):
        if stage == reject_after:
            raise PipelineWriteRejected("run cancelled or superseded")
        checkpoints[stage] = result

    return PipelineContext(
        run_id="run-1",
        job_id="job-1",
        execution_plan={
            "template_id": "general_period_review",
            "template_version": "1.0.0",
            "base_family": "theme_synthesis",
            "report_goal": "Summary",
            "resolved_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "web_policy": "none",
            "illustration_policy": "none",
            "render_policy": "report_html_v1",
        },
        handlers=_handlers(calls, fail_at=fail_at),
        checkpoints=checkpoints,
        assert_current_callback=assert_current,
        save_checkpoint_callback=save,
    )


async def test_fresh_pipeline_executes_fixed_stage_order():
    calls = []
    context = _context(calls=calls)

    await execute_report_job(context)

    assert calls == list(STAGES)
    assert list(context.checkpoints) == list(STAGES)


async def test_resume_after_content_does_not_repeat_paid_stages():
    completed = ["load_evidence", "web_search", "content_generation"]
    calls = []
    context = _context(calls=calls, completed=completed)

    await execute_report_job(context)

    assert calls == ["chart_validation", "illustration", "html_render", "persist"]


async def test_crash_after_render_resumes_at_persist_only():
    calls = []
    first = _context(calls=calls, fail_at="persist")
    with pytest.raises(RuntimeError, match="crash:persist"):
        await execute_report_job(first)
    assert calls == list(STAGES)

    resumed_calls = []
    resumed = _context(
        calls=resumed_calls,
        completed=list(first.checkpoints),
    )
    await execute_report_job(resumed)

    assert resumed_calls == ["persist"]


@pytest.mark.parametrize("rejected_stage", ["load_evidence", "content_generation"])
async def test_cancelled_or_superseded_run_cannot_write_stage_result(rejected_stage):
    calls = []
    context = _context(calls=calls, reject_after=rejected_stage)

    with pytest.raises(PipelineWriteRejected):
        await execute_report_job(context)

    assert rejected_stage not in context.checkpoints
    assert calls[-1] == rejected_stage


def test_stage_order_is_stable_and_execution_plan_is_not_a_stage_input_variant():
    assert STAGES == (
        "load_evidence",
        "web_search",
        "content_generation",
        "chart_validation",
        "illustration",
        "html_render",
        "persist",
    )
    context = _context(calls=[])
    with pytest.raises(ValidationError):
        context.execution_plan.report_goal = "mutated"
