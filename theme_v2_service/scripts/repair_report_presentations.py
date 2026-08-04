#!/usr/bin/env python3
import argparse
import asyncio
import json
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db.session import AsyncSessionFactory, engine
from app.domains.reports.maintenance import repair_report_presentations


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Repair stored Report presentations without provider calls."
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--limit", type=int, default=100)
    return parser.parse_args()


async def _run(*, dry_run: bool, limit: int) -> dict[str, int]:
    try:
        async with AsyncSessionFactory() as session:
            result = await repair_report_presentations(
                session,
                dry_run=dry_run,
                limit=limit,
            )
            if dry_run:
                await session.rollback()
            else:
                await session.commit()
            return {
                "eligible": result.eligible,
                "repaired": result.repaired,
                "skipped_unsafe": result.skipped_unsafe,
            }
    finally:
        await engine.dispose()


def main() -> None:
    args = _arguments()
    result = asyncio.run(_run(dry_run=args.dry_run, limit=args.limit))
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
