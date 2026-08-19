from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Asset
from app.domains.assets.schemas import AssetCreate
from app.domains.assets.service import create_asset, ensure_capture_skills
from app.domains.reports.models import Report
from app.domains.reports.schemas import ReportSpec, ReportSuggestedAction


class ReportActionNotFound(Exception):
    pass


@dataclass(frozen=True)
class ReportActionState:
    id: str
    title: str
    due_at: datetime | None
    created: bool
    todo_asset_id: str | None


async def _owned_report(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
    for_update: bool = False,
) -> Report:
    query = select(Report).where(
        Report.id == report_id,
        Report.user_id == user_id,
    )
    if for_update:
        query = query.with_for_update()
    report = await session.scalar(query)
    if report is None:
        raise ReportActionNotFound()
    return report


def _stored_actions(report: Report) -> list[ReportSuggestedAction]:
    return ReportSpec.model_validate(report.spec_json).suggested_actions


async def _existing_assets(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
) -> dict[str, Asset]:
    assets = list(
        await session.scalars(
            select(Asset).where(
                Asset.user_id == user_id,
                Asset.source_report_id == report_id,
                Asset.source_report_action_id.is_not(None),
            )
        )
    )
    return {
        asset.source_report_action_id: asset
        for asset in assets
        if asset.source_report_action_id
    }


def _state(
    action: ReportSuggestedAction,
    asset: Asset | None,
    *,
    created: bool | None = None,
) -> ReportActionState:
    return ReportActionState(
        id=action.id,
        title=action.title,
        due_at=action.due_at,
        created=(asset is not None) if created is None else created,
        todo_asset_id=asset.id if asset is not None else None,
    )


async def list_report_actions(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
) -> list[ReportActionState]:
    report = await _owned_report(
        session,
        user_id=user_id,
        report_id=report_id,
    )
    assets = await _existing_assets(
        session,
        user_id=user_id,
        report_id=report.id,
    )
    return [_state(action, assets.get(action.id)) for action in _stored_actions(report)]


async def create_report_action_todo(
    session: AsyncSession,
    *,
    user_id: str,
    report_id: str,
    action_id: str,
) -> tuple[ReportActionState, bool]:
    report = await _owned_report(
        session,
        user_id=user_id,
        report_id=report_id,
        for_update=True,
    )
    action = next(
        (item for item in _stored_actions(report) if item.id == action_id),
        None,
    )
    if action is None:
        raise ReportActionNotFound()
    existing = await session.scalar(
        select(Asset)
        .where(
            Asset.user_id == user_id,
            Asset.source_report_id == report.id,
            Asset.source_report_action_id == action.id,
        )
        .with_for_update()
    )
    if existing is not None:
        return _state(action, existing, created=False), False

    skills = await ensure_capture_skills(session, user_id)
    todo_skill = next(skill for skill in skills if skill.machine_name == "todo")
    payload = {
        "title": action.title,
        "domain": "productivity",
    }
    if action.due_at is not None:
        payload["due_date"] = action.due_at.isoformat()
    asset = await create_asset(
        session,
        user_id,
        AssetCreate(
            user_skill_id=todo_skill.id,
            payload=payload,
            effective_at=action.due_at,
        ),
    )
    asset.source_report_id = report.id
    asset.source_report_action_id = action.id
    await session.flush()
    return _state(action, asset, created=True), True
