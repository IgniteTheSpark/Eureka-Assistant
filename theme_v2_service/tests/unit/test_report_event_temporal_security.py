from app.domains.reports.providers import GeneratorRequest
from app.domains.reports.schemas import EvidenceReference, ReportExecutionPlan
from app.domains.reports.security import validate_generator_result


def test_generator_allows_local_event_time_with_event_citation():
    request = GeneratorRequest(
        execution_plan=ReportExecutionPlan(
            template_id="pre_event_briefing",
            template_version="1.0.0",
            base_family="briefing_research",
            report_goal="Prepare for meeting",
            resolved_asset_ids=[],
            resolved_references=[EvidenceReference(kind="event", id="event-1")],
            field_bindings={},
            web_policy="optional",
            illustration_policy="none",
            render_policy="report_html_v1",
        ),
        evidence_bundle={
            "user_evidence": [
                {
                    "kind": "event",
                    "reference_id": "event-1",
                    "temporal_facts": {
                        "timezone": "Asia/Shanghai",
                        "local_date": "2026-08-11",
                        "local_start_time": "21:00",
                        "local_end_time": "22:00",
                        "local_interval_text": "21:00–22:00",
                        "duration_minutes": 60,
                    },
                }
            ]
        },
        template_skill="Use typed evidence only.",
    )
    raw = {
        "content_md": "会议时间为 21:00。[evidence:event-1]",
        "chart_directives": [],
        "illustration_prompt": None,
        "share_card_spec": {
            "headline": "会前调研",
            "summary": "会议时间已确认",
            "highlights": ["21:00 开始"],
            "time_range": "2026-08-11",
        },
        "usage": {"input_tokens": 10, "output_tokens": 20},
    }

    result = validate_generator_result(raw, request=request)

    assert result.content_md == "会议时间为 21:00。[evidence:event-1]"
