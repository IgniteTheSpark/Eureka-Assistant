import pytest

from app.domains.reports.presentation import (
    PresentationRequest,
    render_presentation,
    select_variant,
)
from app.domains.reports.schemas import ReportSuggestedAction


RICH_MARKDOWN = """# 模型不应控制页面标题

这是报告的导语，并包含 <script>alert('x')</script> 原始标签。

:::kpi
记录: 12 条
变化: 稳定
:::

:::timeline
2026-08-01 — 开始记录
2026-08-03 — 完成复盘
:::

:::rank
- 第一项
- 第二项
:::

:::callout{tone=insight}
这是一个可靠洞察。
:::

:::quote
保持持续记录。
— 用户笔记
:::

:::compare
| 维度 | 之前 | 现在 |
| --- | --- | --- |
| 节奏 | 分散 | 稳定 |
:::

[[chart:trend]]

[[chart:missing]]

![外链](https://tracker.example/pixel.png)

:::unknown
Unknown <b>directive</b>
:::
"""


@pytest.mark.parametrize(
    ("family", "seed", "surface", "palette", "color_scheme"),
    [
        ("data_trend", 0, "surface-dashboard", "pal-dashboard", "dark"),
        ("data_trend", 1, "surface-neon", "pal-neon", "dark"),
        ("theme_synthesis", 0, "surface-editorial", "pal-ink", "dark"),
        ("theme_synthesis", 1, "surface-note", "pal-warm", "light"),
        (
            "professional_evaluation",
            0,
            "surface-deck",
            "pal-minimal",
            "light",
        ),
        (
            "professional_evaluation",
            1,
            "surface-forest2",
            "pal-forest",
            "dark",
        ),
        ("briefing_research", 0, "surface-mag", "pal-warm", "light"),
        (
            "briefing_research",
            1,
            "surface-wdash",
            "pal-dashboard",
            "dark",
        ),
    ],
)
def test_catalog_selects_all_eight_variants(
    family: str,
    seed: int,
    surface: str,
    palette: str,
    color_scheme: str,
):
    selected, fallback = select_variant(family, seed)

    assert not fallback
    assert selected.surface == surface
    assert selected.palette == palette
    assert selected.color_scheme == color_scheme


def _request(**overrides) -> PresentationRequest:
    values = {
        "title": "八月复盘",
        "content_md": RICH_MARKDOWN,
        "base_family": "theme_synthesis",
        "seed": 1,
        "chart_svgs": {
            "trend": '<svg role="img"><text>趋势</text></svg>',
        },
        "illustration_url": "/api/files/illustration-1",
        "external_sources": [
            {
                "title": "Research source",
                "url": "https://example.com/research",
                "accessed_at": "2026-08-04T08:00:00Z",
            },
            {
                "title": "Insecure source",
                "url": "http://example.com/insecure",
            },
        ],
        "suggested_actions": [
            ReportSuggestedAction(
                id="action-abc",
                title="准备下一次复盘",
                due_at=None,
            )
        ],
    }
    values.update(overrides)
    return PresentationRequest(**values)


def test_renderer_is_safe_complete_and_deterministic():
    request = _request()

    first = render_presentation(request)
    second = render_presentation(request)

    assert first == second
    assert first.surface == "surface-note"
    assert first.palette == "pal-warm"
    assert first.color_scheme == "light"
    assert 'class="report pal-warm surface-note"' in first.html
    assert "<script" not in first.html
    assert "tracker.example" not in first.html
    assert "http://example.com/insecure" not in first.html
    assert 'src="/api/files/illustration-1"' in first.html
    assert first.html.count("准备下一次复盘") == 1
    assert first.html.count("Research source") == 1
    assert first.html.count("https://example.com/research") == 1
    assert first.html.count('<svg role="img"><text>趋势</text></svg>') == 1
    assert "chart:missing" not in first.html
    assert "Unknown directive" in first.html
    assert "REKA INSIGHTS" in first.html


def test_catalog_has_safe_deterministic_fallback():
    selected, fallback = select_variant("unknown-family", 99)

    assert fallback
    assert selected.surface == "surface-mag"
    assert selected.palette == "pal-warm"


def test_renderer_rejects_unowned_illustration_url():
    result = render_presentation(
        _request(illustration_url="https://tracker.example/image.png")
    )

    assert "tracker.example" not in result.html
    assert result.warnings == ["illustration URL was not owned"]
