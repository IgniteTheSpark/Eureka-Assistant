#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.domains.reports.presentation import FAMILY_VARIANTS
from app.domains.reports.rendering import render_report_presentation
from app.domains.reports.schemas import ReportSuggestedAction


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render all deterministic Report presentation variants."
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        default=ROOT / "tests/fixtures/report_presentation_fixture.md",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / "output/report-presentation-gallery",
    )
    return parser.parse_args()


def _chart_svg() -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 240" '
        'role="img" aria-label="训练负荷趋势">'
        '<rect width="720" height="240" rx="18" fill="#F7F5EF"/>'
        '<polyline points="52,182 196,132 340,148 484,82 668,58" '
        'fill="none" stroke="#B46C4D" stroke-width="5"/>'
        '<g fill="#B46C4D">'
        '<circle cx="52" cy="182" r="6"/><circle cx="196" cy="132" r="6"/>'
        '<circle cx="340" cy="148" r="6"/><circle cx="484" cy="82" r="6"/>'
        '<circle cx="668" cy="58" r="6"/></g></svg>'
    )


def main() -> None:
    args = _arguments()
    content_md = args.fixture.read_text(encoding="utf-8")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    actions = [
        ReportSuggestedAction(
            id="action-fixture-plan",
            title="安排下一次月度训练复盘",
            due_at=datetime(2026, 8, 31, 10, tzinfo=timezone.utc),
        ),
        ReportSuggestedAction(
            id="action-fixture-recovery",
            title="把周三恢复训练加入计划",
        ),
    ]
    sources = [
        {
            "title": "运动训练恢复指南",
            "url": "https://example.com/training-recovery",
            "accessed_at": "2026-08-04T00:00:00Z",
        }
    ]
    manifest = []
    for family, variants in FAMILY_VARIANTS.items():
        for seed, expected in enumerate(variants):
            rendered = render_report_presentation(
                title="七月训练复盘",
                content_md=content_md,
                chart_svgs={"training-load": _chart_svg()},
                media_urls={},
                base_family=family,
                seed=seed,
                external_sources=sources,
                suggested_actions=actions,
            )
            if (
                rendered.surface != expected.surface
                or rendered.palette != expected.palette
                or rendered.color_scheme != expected.color_scheme
            ):
                raise RuntimeError("presentation catalog mismatch")
            path = args.output_dir / f"{family}-{seed}-{rendered.surface}.html"
            encoded = rendered.html.encode("utf-8")
            path.write_bytes(encoded)
            manifest.append(
                {
                    "family": family,
                    "seed": seed,
                    "surface": rendered.surface,
                    "palette": rendered.palette,
                    "color_scheme": rendered.color_scheme,
                    "path": str(path.resolve()),
                    "sha256": hashlib.sha256(encoded).hexdigest(),
                }
            )
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
