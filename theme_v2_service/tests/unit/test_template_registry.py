import json
from pathlib import Path

import pytest

from app.domains.reports.templates import (
    TemplateRegistry,
    TemplateRegistryError,
    get_template_registry,
)


def _manifest(
    template_id: str = "general_period_review",
    version: str = "1.0.0",
    **overrides,
) -> dict:
    value = {
        "id": template_id,
        "version": version,
        "base_family": "theme_synthesis",
        "planner_description": "Summarize a period of user records",
        "data_fit": ["free_text"],
        "analysis_method": "period_synthesis",
        "web_policy": "none",
        "illustration_policy": "optional",
        "render_policy": "report_html_v1",
    }
    value.update(overrides)
    return value


def _package(root: Path, directory: str, manifest: dict, *, skill: bool = True):
    package = root / directory
    package.mkdir(parents=True)
    (package / "template.json").write_text(json.dumps(manifest), encoding="utf-8")
    if skill:
        (package / "SKILL.md").write_text(
            "# Template\n\n## Evidence interpretation\nRules.",
            encoding="utf-8",
        )


@pytest.mark.parametrize(
    ("manifest", "message"),
    [
        (_manifest(version="v1"), "semantic version"),
        (_manifest(web_policy="sometimes"), "web_policy"),
        (_manifest(illustration_policy="always"), "illustration_policy"),
        (_manifest(data_fit=[]), "data_fit"),
    ],
)
def test_registry_rejects_malformed_manifest(tmp_path, manifest, message):
    _package(tmp_path, "invalid", manifest)

    with pytest.raises(TemplateRegistryError, match=message):
        TemplateRegistry.load(tmp_path)


def test_registry_rejects_missing_skill_markdown(tmp_path):
    _package(tmp_path, "missing-skill", _manifest(), skill=False)

    with pytest.raises(TemplateRegistryError, match="SKILL.md"):
        TemplateRegistry.load(tmp_path)


def test_registry_rejects_duplicate_id_and_version(tmp_path):
    manifest = _manifest()
    _package(tmp_path, "first", manifest)
    _package(tmp_path, "second", manifest)

    with pytest.raises(TemplateRegistryError, match="duplicate"):
        TemplateRegistry.load(tmp_path)


def test_get_uses_highest_semver_and_candidates_are_stable(tmp_path):
    _package(tmp_path, "general-v1", _manifest(version="1.2.0"))
    _package(tmp_path, "general-v2", _manifest(version="1.10.0"))
    _package(
        tmp_path,
        "finance",
        _manifest(
            template_id="finance_review",
            data_fit=["counterparty", "time_series_measurement"],
        ),
    )

    registry = TemplateRegistry.load(tmp_path)

    assert registry.get("general_period_review").manifest.version == "1.10.0"
    assert registry.get("general_period_review", "1.2.0").manifest.version == "1.2.0"
    assert [
        (package.manifest.id, package.manifest.version)
        for package in registry.candidates_for({"free_text", "counterparty"})
    ] == [
        ("finance_review", "1.0.0"),
        ("general_period_review", "1.10.0"),
        ("general_period_review", "1.2.0"),
    ]


def test_repository_contains_exact_phase_one_packages():
    root = Path(__file__).parents[2] / "report-templates"
    registry = TemplateRegistry.load(root)

    assert registry.template_ids == {
        "child_growth_review",
        "finance_review",
        "idea_synthesis",
        "work_monthly_review",
        "tennis_monthly_review",
        "learning_review",
        "pre_event_briefing",
        "general_period_review",
    }
    assert all(package.skill_markdown for package in registry.packages)
    assert get_template_registry().template_ids == registry.template_ids
