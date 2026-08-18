import pytest
from pydantic import ValidationError

from app.domains.reports.schemas import (
    EvidenceReference,
    EvidenceScope,
    PendingDecision,
    ReportPlanDraft,
    ReportScopeDraft,
    TimeRange,
    RunGenerateRequest,
)
from app.domains.reports.scope_adapters import (
    ScopeMatchTerm,
    ScopeRecordGroup,
    initial_scope,
)
from app.domains.reports.planner import (
    InvalidPlannerResult,
    PlannerRequest,
    PlannerResult,
    PlannerTemplate,
    validate_planner_result_against_request,
)
from app.domains.reports.schemas import (
    CapabilityPolicy,
    IllustrationPolicy,
    ReportPlanOption,
)
from datetime import datetime, timezone


def test_plan_draft_accepts_typed_event_contact_and_asset_references():
    draft = ReportPlanDraft.model_validate(
        {
            "selected_option_id": "recommended",
            "attention_questions": ["球队建设的当前短板是什么？"],
            "additional_focus": "补充 Kevin 的公开职业背景",
            "evidence_scope": {
                "references": [
                    {"kind": "event", "id": "event-1"},
                    {"kind": "contact", "id": "contact-1"},
                    {"kind": "asset", "id": "asset-1"},
                ]
            },
            "public_research_scope": {
                "entities": [],
                "questions": [],
                "freshness": "current",
            },
            "blockers": [],
        }
    )

    assert [ref.kind for ref in draft.evidence_scope.references] == [
        "event",
        "contact",
        "asset",
    ]
    assert draft.evidence_scope.asset_ids == ["asset-1"]


def test_legacy_asset_ids_are_normalized_into_typed_references():
    scope = EvidenceScope(asset_ids=["asset-1", "asset-1", "asset-2"])

    assert [(ref.kind, ref.id) for ref in scope.references] == [
        ("asset", "asset-1"),
        ("asset", "asset-2"),
    ]
    assert scope.asset_ids == ["asset-1", "asset-2"]


def test_typed_references_are_deduplicated_without_losing_order():
    scope = EvidenceScope.model_validate(
        {
            "asset_ids": ["asset-2"],
            "references": [
                {"kind": "event", "id": "event-1"},
                {"kind": "asset", "id": "asset-1"},
                {"kind": "event", "id": "event-1"},
            ],
        }
    )

    assert [(ref.kind, ref.id) for ref in scope.references] == [
        ("event", "event-1"),
        ("asset", "asset-1"),
        ("asset", "asset-2"),
    ]
    assert scope.asset_ids == ["asset-1", "asset-2"]


def test_generate_request_requires_plan_revision():
    request = RunGenerateRequest(
        selected_option_id="recommended",
        expected_plan_revision=3,
    )
    assert request.expected_plan_revision == 3

    with pytest.raises(ValidationError):
        RunGenerateRequest(selected_option_id="recommended")


def test_public_research_person_entity_can_carry_a_qualifier():
    draft = ReportPlanDraft.model_validate(
        {
            "selected_option_id": "recommended",
            "evidence_scope": {},
            "public_research_scope": {
                "entities": [
                    {
                        "id": "kevin",
                        "kind": "person",
                        "name": "Kevin",
                        "qualifier": "Eureka CEO",
                    }
                ],
                "questions": ["公开职业背景"],
            },
        }
    )

    assert draft.public_research_scope.entities[0].qualifier == "Eureka CEO"


def test_pre_event_scope_projects_primary_event_before_supporting_references():
    draft = ReportScopeDraft(
        adapter_kind="pre_event_briefing",
        primary_reference=EvidenceReference(kind="event", id="event-1"),
        supporting_references=[
            EvidenceReference(kind="contact", id="contact-1"),
            EvidenceReference(kind="asset", id="asset-1"),
        ],
    )

    assert draft.to_evidence_scope().references == [
        EvidenceReference(kind="event", id="event-1"),
        EvidenceReference(kind="contact", id="contact-1"),
        EvidenceReference(kind="asset", id="asset-1"),
    ]


def test_pre_event_scope_rejects_a_non_event_primary_reference():
    with pytest.raises(ValidationError):
        ReportScopeDraft(
            adapter_kind="pre_event_briefing",
            primary_reference=EvidenceReference(kind="asset", id="asset-1"),
        )


def test_period_summary_scope_accepts_multiple_skills_and_records():
    draft = ReportScopeDraft.model_validate(
        {
            "adapter_kind": "period_summary",
            "skill_ids": ["water", "running", "water"],
            "supporting_references": [
                {"kind": "asset", "id": "water-1"},
                {"kind": "asset", "id": "run-1"},
            ],
            "time_range": {
                "from": "2026-08-10T00:00:00+08:00",
                "to": "2026-08-17T00:00:00+08:00",
            },
        }
    )

    assert draft.skill_ids == ["water", "running"]
    assert [reference.id for reference in draft.to_evidence_scope().references] == [
        "water-1",
        "run-1",
    ]


@pytest.mark.parametrize(
    "payload",
    [
        {"from": "2026-08-10T00:00:00", "to": "2026-08-11T00:00:00Z"},
        {"from": "2026-08-10T00:00:00+08:00", "to": "2026-08-11T00:00:00"},
    ],
)
def test_report_time_range_rejects_naive_boundaries(payload):
    with pytest.raises(ValidationError, match="timezone offset"):
        TimeRange.model_validate(payload)


def test_report_time_range_accepts_non_utc_midnight_boundaries():
    value = TimeRange.model_validate(
        {
            "from": "2026-08-10T00:00:00+08:00",
            "to": "2026-08-11T00:00:00+08:00",
        }
    )

    assert value.from_at.utcoffset().total_seconds() == 8 * 60 * 60
    assert value.to_at.utcoffset().total_seconds() == 8 * 60 * 60


def test_scope_confirmation_is_a_first_class_pending_decision():
    decision = PendingDecision(
        type="scope_confirmation",
        adapter_kind="pre_event_briefing",
    )

    assert decision.model_dump(exclude_none=True) == {
        "type": "scope_confirmation",
        "questions": [],
        "adapter_kind": "pre_event_briefing",
    }


def test_report_scope_keeps_presentation_and_supplemental_text_separate():
    draft = ReportScopeDraft.model_validate(
        {
            "adapter_kind": "period_summary",
            "presentation_preference": {
                "family": "data_trend",
                "custom_text": "",
            },
            "additional_focus": "重点解释周末支出增加的原因",
        }
    )

    assert draft.presentation_preference.family == "data_trend"
    assert draft.presentation_preference.custom_text == ""
    assert draft.additional_focus == "重点解释周末支出增加的原因"


def test_custom_presentation_does_not_overwrite_supplemental_text():
    draft = ReportScopeDraft.model_validate(
        {
            "adapter_kind": "period_summary",
            "presentation_preference": {
                "family": "custom",
                "custom_text": "做成适合分享给家人的一页卡片",
            },
            "additional_focus": "忽略报销项目",
        }
    )

    assert draft.presentation_preference.custom_text == "做成适合分享给家人的一页卡片"
    assert draft.additional_focus == "忽略报销项目"


def test_vague_recent_period_remains_unresolved_until_user_confirms_time():
    draft = initial_scope(
        "我想总结一下最近的消费",
        now=datetime(2026, 8, 18, 4, 0, tzinfo=timezone.utc),
        timezone_name="Asia/Shanghai",
    )

    assert draft.adapter_kind == "period_summary"
    assert draft.time_range is None
    assert draft.missing_dimensions == ["time_range"]


def test_explicit_30_day_period_is_resolved_and_not_missing():
    draft = initial_scope(
        "总结过去30天的消费",
        now=datetime(2026, 8, 18, 4, 0, tzinfo=timezone.utc),
        timezone_name="Asia/Shanghai",
    )

    assert draft.time_range is not None
    assert draft.time_range.from_at is not None
    assert draft.time_range.to_at is not None
    assert draft.time_range.to_at - draft.time_range.from_at == __import__(
        "datetime"
    ).timedelta(days=30)
    assert draft.missing_dimensions == []


def test_record_group_matching_metadata_stays_internal():
    group = ScopeRecordGroup(
        skill_id="skill-running",
        machine_name="running_log",
        match_terms=["running", "跑步"],
        identity_match_terms=["running", "跑步"],
        match_specs=[
            ScopeMatchTerm(
                value="跑步",
                provenance="identity",
                is_alias=True,
            )
        ],
        label="跑步记录",
        count=0,
    )

    assert group.model_dump() == {
        "skill_id": "skill-running",
        "label": "跑步记录",
        "count": 0,
        "default_selected": True,
        "records": [],
    }


def test_standard_presentation_family_is_a_hard_planner_constraint():
    request = PlannerRequest(
        run_id="run-1",
        origin="user_initiated",
        intent="总结消费",
        launch_context={},
        answers={},
        scope_draft=ReportScopeDraft.model_validate(
            {
                "adapter_kind": "period_summary",
                "presentation_preference": {"family": "data_trend"},
            }
        ),
        evidence_scope=EvidenceScope(),
        primary_skills=[],
        related_skills=[],
        asset_summaries=[],
        templates=[
            PlannerTemplate(
                id="general_period_review",
                version="1.0.0",
                base_family="theme_synthesis",
                planner_description="通用复盘",
                data_fit=["free_text"],
                analysis_method="period_summary",
                web_policy="none",
                illustration_policy="none",
                render_policy="report_html_v1",
                skill_markdown="Use evidence only.",
            )
        ],
    )
    result = PlannerResult(
        options=[
            ReportPlanOption(
                id="option-1",
                recommended=True,
                title="主题综合",
                summary="总结消费",
                report_goal="总结消费",
                template_id="general_period_review",
                template_version="1.0.0",
                base_family="theme_synthesis",
                evidence_scope=EvidenceScope(),
                web_search=CapabilityPolicy(policy="none"),
                illustration=IllustrationPolicy(policy="none"),
                render_policy="report_html_v1",
            )
        ]
    )

    with pytest.raises(InvalidPlannerResult, match="presentation preference"):
        validate_planner_result_against_request(request=request, result=result)
