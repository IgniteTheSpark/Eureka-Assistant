from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class TimeRange(StrictModel):
    from_at: datetime | None = Field(default=None, alias="from")
    to_at: datetime | None = Field(default=None, alias="to")


EvidenceKind = Literal["asset", "event", "contact"]
ScopeAdapterKind = Literal["pre_event_briefing", "period_summary", "generic"]


class EvidenceReference(StrictModel):
    kind: EvidenceKind
    id: str = Field(min_length=1)


class EvidenceScope(StrictModel):
    time_range: TimeRange | None = None
    skill_ids: list[str] = Field(default_factory=list)
    asset_ids: list[str] = Field(default_factory=list)
    references: list[EvidenceReference] = Field(default_factory=list)
    counts_by_skill: dict[str, int] = Field(default_factory=dict)

    @model_validator(mode="after")
    def normalize_references(self) -> "EvidenceScope":
        normalized: list[EvidenceReference] = []
        seen: set[tuple[str, str]] = set()
        candidates = [
            *self.references,
            *(EvidenceReference(kind="asset", id=value) for value in self.asset_ids),
        ]
        for reference in candidates:
            key = (reference.kind, reference.id)
            if key in seen:
                continue
            seen.add(key)
            normalized.append(reference)
        self.references = normalized
        self.asset_ids = [
            reference.id
            for reference in normalized
            if reference.kind == "asset"
        ]
        return self


class ReportScopeDraft(StrictModel):
    adapter_kind: ScopeAdapterKind
    primary_reference: EvidenceReference | None = None
    supporting_references: list[EvidenceReference] = Field(default_factory=list)
    skill_ids: list[str] = Field(default_factory=list)
    time_range: TimeRange | None = None
    attention_focus: list[str] = Field(default_factory=list, max_length=8)
    additional_focus: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def normalize_and_validate(self) -> "ReportScopeDraft":
        self.skill_ids = list(dict.fromkeys(self.skill_ids))
        normalized: list[EvidenceReference] = []
        seen: set[tuple[str, str]] = set()
        primary_key = None
        if self.primary_reference is not None:
            primary_key = (self.primary_reference.kind, self.primary_reference.id)
        for reference in self.supporting_references:
            key = (reference.kind, reference.id)
            if key == primary_key or key in seen:
                continue
            seen.add(key)
            normalized.append(reference)
        self.supporting_references = normalized
        if (
            self.adapter_kind == "pre_event_briefing"
            and self.primary_reference is not None
            and self.primary_reference.kind != "event"
        ):
            raise ValueError("pre-event primary reference must be an Event")
        return self

    def to_evidence_scope(self) -> EvidenceScope:
        references = []
        if self.primary_reference is not None:
            references.append(self.primary_reference)
        references.extend(self.supporting_references)
        return EvidenceScope(
            time_range=self.time_range,
            skill_ids=self.skill_ids,
            references=references,
        )


class ReportScopeDraftUpdate(StrictModel):
    expected_revision: int = Field(ge=0)
    draft: ReportScopeDraft


class ReportScopePrepareRequest(StrictModel):
    expected_revision: int = Field(ge=0)


class ResearchEntity(StrictModel):
    id: str = Field(min_length=1)
    kind: Literal["organization", "person", "topic", "product", "place"]
    name: str = Field(min_length=1, max_length=200)
    qualifier: str | None = Field(default=None, max_length=200)
    enabled: bool = True


class PublicResearchBrief(StrictModel):
    entities: list[ResearchEntity] = Field(default_factory=list)
    questions: list[str] = Field(default_factory=list, max_length=8)
    freshness: Literal[
        "current",
        "recent_year",
        "historical",
        "not_applicable",
    ] = "current"


class PlanBlocker(StrictModel):
    code: Literal[
        "ambiguous_person",
        "missing_public_entity",
        "empty_scope",
    ]
    message: str = Field(min_length=1, max_length=500)
    entity_id: str | None = None


class ReportPlanDraft(StrictModel):
    selected_option_id: str = Field(min_length=1)
    attention_questions: list[str] = Field(default_factory=list, max_length=8)
    additional_focus: str = Field(default="", max_length=500)
    evidence_scope: EvidenceScope = Field(default_factory=EvidenceScope)
    public_research_scope: PublicResearchBrief = Field(
        default_factory=PublicResearchBrief
    )
    blockers: list[PlanBlocker] = Field(default_factory=list)


class ClarificationQuestion(StrictModel):
    id: str
    question: str
    options: list[str] = Field(default_factory=list)
    required: bool = True


class PendingDecision(StrictModel):
    type: Literal["scope_confirmation", "clarification", "plan_selection"]
    questions: list[ClarificationQuestion] = Field(default_factory=list)
    recommended_option_id: str | None = None
    adapter_kind: ScopeAdapterKind | None = None

    @model_validator(mode="after")
    def validate_shape(self) -> "PendingDecision":
        if self.type == "clarification" and not self.questions:
            raise ValueError("clarification requires questions")
        if self.type == "plan_selection" and not self.recommended_option_id:
            raise ValueError("plan_selection requires recommended_option_id")
        if self.type == "scope_confirmation" and self.adapter_kind is None:
            raise ValueError("scope_confirmation requires adapter_kind")
        return self


class CapabilityPolicy(StrictModel):
    policy: Literal["none", "optional", "required", "authoritative_only"]
    reason: str | None = None


class IllustrationPolicy(StrictModel):
    policy: Literal["none", "optional", "required"]
    reason: str | None = None


class ReportPlanOption(StrictModel):
    id: str
    recommended: bool
    title: str
    summary: str
    report_goal: str
    template_id: str
    template_version: str
    base_family: Literal[
        "data_trend",
        "theme_synthesis",
        "professional_evaluation",
        "briefing_research",
    ]
    evidence_scope: EvidenceScope
    attention_questions: list[str] = Field(default_factory=list, max_length=8)
    public_research_scope: PublicResearchBrief = Field(
        default_factory=PublicResearchBrief
    )
    blockers: list[PlanBlocker] = Field(default_factory=list)
    field_bindings: dict[str, str] = Field(default_factory=dict)
    web_search: CapabilityPolicy
    illustration: IllustrationPolicy
    render_policy: str


class ReportExecutionPlan(StrictModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True, frozen=True)

    template_id: str
    template_version: str
    base_family: str
    report_goal: str
    resolved_asset_ids: list[str]
    resolved_references: list[EvidenceReference] = Field(default_factory=list)
    attention_questions: list[str] = Field(default_factory=list)
    public_research_brief: PublicResearchBrief = Field(
        default_factory=PublicResearchBrief
    )
    field_bindings: dict[str, str] = Field(default_factory=dict)
    time_range: TimeRange | None = None
    web_policy: Literal["none", "optional", "required", "authoritative_only"]
    illustration_policy: Literal["none", "optional", "required"]
    render_policy: str


class CapabilityExecution(StrictModel):
    policy: str
    status: Literal[
        "not_requested",
        "pending",
        "succeeded",
        "failed_degraded",
        "failed_fatal",
        "skipped",
    ]
    sources: list[dict] = Field(default_factory=list)
    file_ids: list[str] = Field(default_factory=list)


class GenerationContext(StrictModel):
    web_search: CapabilityExecution | None = None
    illustration: CapabilityExecution | None = None
    warnings: list[str] = Field(default_factory=list)


class ReportCitation(StrictModel):
    model_config = ConfigDict(
        extra="forbid",
        populate_by_name=True,
        frozen=True,
    )

    paragraph_hash: str
    asset_ids: list[str] = Field(default_factory=list)
    source_urls: list[str] = Field(default_factory=list)


class ReportSuggestedAction(StrictModel):
    model_config = ConfigDict(
        extra="forbid",
        populate_by_name=True,
        frozen=True,
    )

    id: str
    title: str = Field(min_length=1, max_length=200)
    due_at: datetime | None = None


class ReportSpec(StrictModel):
    template_id: str
    template_version: str
    base_family: str
    source_asset_ids: list[str] = Field(default_factory=list)
    unavailable_asset_ids: list[str] = Field(default_factory=list)
    field_bindings: dict[str, str] = Field(default_factory=dict)
    time_range: TimeRange | None = None
    external_sources: list[dict] = Field(default_factory=list)
    web_policy: str
    generated_file_ids: list[str] = Field(default_factory=list)
    surface: str = "report"
    palette: str = "calm"
    seed: int = 0
    citations: list[ReportCitation] = Field(default_factory=list)
    suggested_actions: list[ReportSuggestedAction] = Field(default_factory=list)
    presentation_version: str = "report_html_v2"


class ShareCardSpec(StrictModel):
    headline: str
    summary: str
    highlights: list[str] = Field(default_factory=list, max_length=3)
    time_range: str
    illustration_file_id: str | None = None


class UserRunCreate(StrictModel):
    origin: Literal["user_initiated"] = "user_initiated"
    intent: str = Field(min_length=1)
    skill_ids: list[str] = Field(default_factory=list)
    asset_ids: list[str] = Field(default_factory=list)
    time_range: TimeRange | None = None

    def to_evidence_scope(self) -> EvidenceScope:
        return EvidenceScope(
            time_range=self.time_range,
            skill_ids=self.skill_ids,
            asset_ids=self.asset_ids,
        )


class TriggerRunCreate(StrictModel):
    origin: Literal["trigger"]
    trigger_execution_id: str


ReportRunCreate = Annotated[
    UserRunCreate | TriggerRunCreate,
    Field(discriminator="origin"),
]


class RunDecisionRequest(StrictModel):
    answers: dict = Field(default_factory=dict)
    evidence_scope: EvidenceScope | None = None


class ReportPlanDraftUpdate(StrictModel):
    expected_revision: int = Field(ge=0)
    selected_option_id: str = Field(min_length=1)
    attention_questions: list[str] = Field(default_factory=list, max_length=8)
    additional_focus: str = Field(default="", max_length=500)
    evidence_scope: EvidenceScope = Field(default_factory=EvidenceScope)
    public_research_scope: PublicResearchBrief = Field(
        default_factory=PublicResearchBrief
    )


class RunGenerateRequest(StrictModel):
    selected_option_id: str
    expected_plan_revision: int = Field(ge=0)
