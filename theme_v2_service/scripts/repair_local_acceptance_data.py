#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path

from sqlalchemy import select


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db.models import Asset, UserSkill
from app.db.session import AsyncSessionFactory, engine
from app.domains.assets.validation import normalize_payload_schema
from app.domains.reports import models as report_models  # noqa: F401


KNOWN_ACCEPTANCE_MARKER = "theme-v2-acceptance-2026-08-04"
WATER_REPAIRS: dict[str, tuple[str | None, datetime | None]] = {
    "bad6911c-d87d-4879-b451-c822d8f12e52": (
        None,
        datetime(2026, 8, 4, 16, 13, 25, 452365),
    ),
    "52d40b6f-da15-4b1e-bfb3-889c4199d1ad": (
        "晚上",
        datetime(2026, 8, 4, 12, 0),
    ),
    "b441bb44-7ba5-475b-8e89-658612c750de": ("下午", None),
    "e7339e76-31d6-40dd-96c4-10fadaac9597": ("上午", None),
}


def repair_payload(payload: dict) -> dict:
    repaired = dict(payload)
    if repaired.get("acceptance_marker") == KNOWN_ACCEPTANCE_MARKER:
        repaired.pop("acceptance_marker")
    return repaired


async def repair_local_data(*, dry_run: bool) -> dict:
    changed: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    async with AsyncSessionFactory() as session:
        rows = (
            await session.execute(
                select(Asset, UserSkill).join(
                    UserSkill,
                    Asset.user_skill_id == UserSkill.id,
                )
            )
        ).all()
        for asset, skill in rows:
            payload = dict(asset.payload_json or {})
            next_payload = payload
            changes: list[str] = []

            if payload.get("acceptance_marker") == KNOWN_ACCEPTANCE_MARKER:
                properties = normalize_payload_schema(skill.schema_json).get(
                    "properties",
                    {},
                )
                if "acceptance_marker" in properties:
                    skipped.append(
                        {"id": asset.id, "reason": "marker is schema-defined"}
                    )
                else:
                    next_payload = repair_payload(payload)
                    changes.append("remove_acceptance_marker")

            water_repair = WATER_REPAIRS.get(asset.id)
            if water_repair is not None:
                if skill.machine_name != "daily_water_intake":
                    skipped.append(
                        {"id": asset.id, "reason": "unexpected water skill"}
                    )
                else:
                    period, occurred_at = water_repair
                    if asset.period != period:
                        changes.append(f"period:{period or 'null'}")
                    if asset.occurred_at != occurred_at:
                        changes.append(
                            f"occurred_at:{occurred_at.isoformat() if occurred_at else 'null'}"
                        )
                    if not dry_run:
                        asset.period = period
                        asset.occurred_at = occurred_at

            if changes:
                changed.append(
                    {
                        "id": asset.id,
                        "skill": skill.machine_name,
                        "changes": ",".join(changes),
                    }
                )
                if not dry_run and next_payload != payload:
                    asset.payload_json = next_payload

        if dry_run:
            await session.rollback()
        else:
            await session.commit()
    return {
        "mode": "dry-run" if dry_run else "apply",
        "changed_count": len(changed),
        "changed": changed,
        "skipped_count": len(skipped),
        "skipped": skipped,
    }


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Repair only the known local Theme V2 acceptance records.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    return parser.parse_args()


async def _run_command(args: argparse.Namespace) -> None:
    try:
        result = await repair_local_data(dry_run=args.dry_run)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    finally:
        await engine.dispose()


def main() -> None:
    asyncio.run(_run_command(_arguments()))


if __name__ == "__main__":
    main()
