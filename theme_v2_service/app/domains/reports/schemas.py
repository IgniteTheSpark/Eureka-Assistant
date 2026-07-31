from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class TimeRange(StrictModel):
    from_at: datetime | None = Field(default=None, alias="from")
    to_at: datetime | None = Field(default=None, alias="to")


class EvidenceScope(StrictModel):
    time_range: TimeRange | None = None
    skill_ids: list[str] = Field(default_factory=list)
    asset_ids: list[str] = Field(default_factory=list)
    counts_by_skill: dict[str, int] = Field(default_factory=dict)


class ClarificationQuestion(StrictModel):
    id: str
    question: str
    options: list[str] = Field(default_factory=list)
    required: bool = True


class PendingDecision(StrictModel):
    type: Literal["clarification", "plan_selection"]
    questions: list[ClarificationQuestion] = Field(default_factory=list)
    recommended_option_id: str | None = None

    @model_validator(mode="after")
    def validate_shape(self) -> "PendingDecision":
        if self.type == "clarification" and not self.questions:
            raise ValueError("clarification requires questions")
        if self.type == "plan_selection" and not self.recommended_option_id:
            raise ValueError("plan_selection requires recommended_option_id")
        return self


class CapabilityPolicy(StrictModel):
    policy: Literal["none", "optional", "required", "authoritative_only"]
    reason: str | None = None


class IllustrationPolicy(StrictModel):
    policy: Literal["none", "optional", "required"]
    reason: str | None = None


class ReportPlanOption(StrictModel):
    id: str
    recommended: bool = False
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


class RunGenerateRequest(StrictModel):
    selected_option_id: str
