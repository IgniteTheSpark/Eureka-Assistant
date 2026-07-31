from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import ReportExecutionPlan, TimeRange
from app.domains.reports.templates import TemplateRegistry


class InsufficientEvidence(ValueError):
    pass


class EvidenceModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class EvidenceItem(EvidenceModel):
    asset_id: str
    skill_id: str
    effective_at: datetime
    payload: dict
    bound_fields: dict[str, Any] = Field(default_factory=dict)


class EvidenceBundle(EvidenceModel):
    user_evidence: list[EvidenceItem]
    unavailable_asset_ids: list[str]
    field_bindings: dict[str, str]
    time_range: TimeRange | None
    report_goal: str
    template: dict[str, str]
    launch_context: dict = Field(default_factory=dict)


def _resolve_path(asset: Asset, path: str) -> Any:
    if path == "effective_at":
        return asset.effective_at or asset.created_at
    if not path.startswith("payload."):
        return None
    value: Any = asset.payload_json
    for part in path.removeprefix("payload.").split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def _minimum_data_satisfied(
    *,
    run: ReportGenerationRun,
    available_count: int,
) -> bool:
    if available_count > 0:
        return True
    return bool(run.launch_context.get("event_id"))


async def load_latest_evidence(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    execution_plan: ReportExecutionPlan,
    registry: TemplateRegistry,
) -> EvidenceBundle:
    package = registry.get(
        execution_plan.template_id,
        execution_plan.template_version,
    )
    if package.manifest.base_family != execution_plan.base_family:
        raise InsufficientEvidence("execution plan does not match template")

    requested_ids = list(dict.fromkeys(execution_plan.resolved_asset_ids))
    rows = []
    if requested_ids:
        rows = list(
            await session.scalars(
                select(Asset).where(
                    Asset.id.in_(requested_ids),
                    Asset.user_id == run.user_id,
                )
            )
        )
    by_id = {asset.id: asset for asset in rows}
    evidence: list[EvidenceItem] = []
    unavailable: list[str] = []
    for asset_id in requested_ids:
        asset = by_id.get(asset_id)
        if asset is None:
            unavailable.append(asset_id)
            continue
        evidence.append(
            EvidenceItem(
                asset_id=asset.id,
                skill_id=asset.user_skill_id,
                effective_at=asset.effective_at or asset.created_at,
                payload=asset.payload_json,
                bound_fields={
                    binding: _resolve_path(asset, source)
                    for binding, source in execution_plan.field_bindings.items()
                },
            )
        )

    if not _minimum_data_satisfied(run=run, available_count=len(evidence)):
        raise InsufficientEvidence(
            f"template {package.manifest.id} minimum data is not satisfied"
        )
    return EvidenceBundle(
        user_evidence=evidence,
        unavailable_asset_ids=unavailable,
        field_bindings=execution_plan.field_bindings,
        time_range=execution_plan.time_range,
        report_goal=execution_plan.report_goal,
        template={
            "id": package.manifest.id,
            "version": package.manifest.version,
        },
        launch_context=dict(run.launch_context),
    )
