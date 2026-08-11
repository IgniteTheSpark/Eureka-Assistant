import pytest
from pydantic import ValidationError

from app.domains.reports.schemas import (
    EvidenceReference,
    EvidenceScope,
    PendingDecision,
    ReportPlanDraft,
    ReportScopeDraft,
    RunGenerateRequest,
)


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
