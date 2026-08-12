from datetime import datetime

import pytest

from app.domains.reports.normalization import normalize_report_content
from app.domains.reports.providers import GeneratedSuggestedAction


def _source(url: str = "https://example.com/research") -> dict:
    return {
        "title": "Research",
        "url": url,
        "snippet": "A grounded public source.",
        "accessed_at": "2026-08-04T08:00:00Z",
        "authoritative": True,
    }


def test_normalizer_removes_citation_tags_and_keeps_paragraph_manifest():
    normalized = normalize_report_content(
        content_md=(
            "第一段来自记录。[evidence:asset-1]\n\n"
            "外部结论。[source:https://example.com/research]"
        ),
        allowed_asset_ids=["asset-1"],
        external_sources=[_source(), _source("https://unused.example/source")],
        suggested_actions=[
            GeneratedSuggestedAction(title="  准备   访谈问题  ", due_at=None)
        ],
    )

    assert normalized.content_md == "第一段来自记录。\n\n外部结论。"
    assert normalized.citations[0].asset_ids == ["asset-1"]
    assert normalized.citations[0].source_urls == []
    assert normalized.citations[1].asset_ids == []
    assert normalized.citations[1].source_urls == [
        "https://example.com/research"
    ]
    assert normalized.suggested_actions[0].title == "准备 访谈问题"
    assert normalized.suggested_actions[0].id.startswith("action-")
    assert [source["url"] for source in normalized.used_external_sources] == [
        "https://example.com/research"
    ]


def test_normalizer_removes_double_wrapped_citations_without_empty_brackets():
    normalized = normalize_report_content(
        content_md="本期总支出为 681 元。[[evidence:asset-1]]",
        allowed_asset_ids=["asset-1"],
        external_sources=[],
        suggested_actions=[],
    )

    assert normalized.content_md == "本期总支出为 681 元。"
    assert "[]" not in normalized.content_md
    assert normalized.citations[0].asset_ids == ["asset-1"]


def test_normalizer_keeps_generic_event_evidence_and_asset_compatibility():
    normalized = normalize_report_content(
        content_md=(
            "会议时间是 21:00。[evidence:event-1]\n\n"
            "跑步记录为 5 公里。[evidence:asset-1]"
        ),
        allowed_evidence_ids=["event-1", "asset-1"],
        allowed_asset_ids=["asset-1"],
        external_sources=[],
        suggested_actions=[],
    )

    assert normalized.citations[0].evidence_ids == ["event-1"]
    assert normalized.citations[0].asset_ids == []
    assert normalized.citations[1].evidence_ids == ["asset-1"]
    assert normalized.citations[1].asset_ids == ["asset-1"]


def test_action_ids_are_stable_and_include_position_title_and_due_time():
    due_at = datetime.fromisoformat("2026-08-10T09:00:00+08:00")
    action = GeneratedSuggestedAction(title="准备访谈问题", due_at=due_at)

    first = normalize_report_content(
        content_md="正文",
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[action],
    )
    repeated = normalize_report_content(
        content_md="正文",
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[action],
    )
    moved = normalize_report_content(
        content_md="正文",
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[
            GeneratedSuggestedAction(title="另一项", due_at=None),
            action,
        ],
    )

    assert first.suggested_actions[0].id == repeated.suggested_actions[0].id
    assert first.suggested_actions[0].id != moved.suggested_actions[1].id
    assert first.suggested_actions[0].due_at == due_at


def test_legacy_actions_are_extracted_only_when_typed_actions_are_empty():
    legacy = normalize_report_content(
        content_md=(
            "正文\n\n:::actions\n"
            "- **准备**问题\n"
            "2. 安排访谈\n"
            ":::\n\n结尾"
        ),
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[],
    )
    typed = normalize_report_content(
        content_md="正文\n\n:::actions\n- 旧行动\n:::",
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[
            GeneratedSuggestedAction(title="新行动", due_at=None)
        ],
    )

    assert ":::actions" not in legacy.content_md
    assert [item.title for item in legacy.suggested_actions] == [
        "准备问题",
        "安排访谈",
    ]
    assert ":::actions" not in typed.content_md
    assert [item.title for item in typed.suggested_actions] == ["新行动"]


def test_normalizer_rejects_unknown_and_malformed_citations():
    with pytest.raises(ValueError, match="unknown report citation"):
        normalize_report_content(
            content_md="正文。[evidence:asset-other]",
            allowed_asset_ids=["asset-1"],
            external_sources=[],
            suggested_actions=[],
        )
    with pytest.raises(ValueError, match="malformed report citation"):
        normalize_report_content(
            content_md="正文。[evidence:asset-1",
            allowed_asset_ids=["asset-1"],
            external_sources=[],
            suggested_actions=[],
        )


def test_normalizer_limits_legacy_actions_to_five():
    normalized = normalize_report_content(
        content_md=(
            ":::actions\n"
            "- 一\n- 二\n- 三\n- 四\n- 五\n- 六\n"
            ":::"
        ),
        allowed_asset_ids=[],
        external_sources=[],
        suggested_actions=[],
    )

    assert [item.title for item in normalized.suggested_actions] == [
        "一",
        "二",
        "三",
        "四",
        "五",
    ]
