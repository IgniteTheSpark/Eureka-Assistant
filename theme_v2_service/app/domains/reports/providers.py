from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Protocol

from pydantic import BaseModel, ConfigDict, Field

from app.domains.reports.charts import ChartDirective
from app.domains.reports.schemas import ReportExecutionPlan, ShareCardSpec

if TYPE_CHECKING:
    from app.domains.reports.planner import PlannerRequest, PlannerResult


class ProviderModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ProviderError(RuntimeError):
    pass


class RetryableProviderError(ProviderError):
    pass


class PermanentProviderError(ProviderError):
    pass


class GeneratorRequest(ProviderModel):
    execution_plan: ReportExecutionPlan
    evidence_bundle: dict
    template_skill: str
    external_sources: list[dict] = Field(default_factory=list)


class GeneratorUsage(ProviderModel):
    input_tokens: int = Field(default=0, ge=0)
    output_tokens: int = Field(default=0, ge=0)
    model_profile: str = "report_generator"


class GeneratedSuggestedAction(ProviderModel):
    title: str = Field(min_length=1, max_length=200)
    due_at: datetime | None = None


class GeneratorResult(ProviderModel):
    content_md: str = Field(min_length=1)
    chart_directives: list[ChartDirective] = Field(default_factory=list)
    illustration_prompt: str | None = None
    suggested_actions: list[GeneratedSuggestedAction] = Field(
        default_factory=list,
        max_length=5,
    )
    share_card_spec: ShareCardSpec
    usage: GeneratorUsage = Field(default_factory=GeneratorUsage)


class WebSource(ProviderModel):
    title: str
    url: str
    snippet: str
    accessed_at: str
    authoritative: bool = False


class GeneratedImage(ProviderModel):
    data: bytes
    mime_type: str


class ReportPlannerProvider(Protocol):
    async def plan(self, request: PlannerRequest) -> PlannerResult:
        ...


class ReportGeneratorProvider(Protocol):
    async def generate(self, request: GeneratorRequest) -> GeneratorResult:
        ...


class WebSearchProvider(Protocol):
    async def search(self, queries: list[str]) -> list[WebSource]:
        ...


class UnavailableWebSearchProvider:
    async def search(self, queries: list[str]) -> list[WebSource]:
        raise PermanentProviderError("report Web Search is not enabled")


class IllustrationProvider(Protocol):
    async def generate(self, prompt: str) -> GeneratedImage:
        ...


class UnavailableIllustrationProvider:
    async def generate(self, prompt: str) -> GeneratedImage:
        raise PermanentProviderError("illustration provider is not configured")
