from app.domains.reports.rendering import (
    render_report_html,
    render_report_presentation,
)


def test_renderer_strips_scripts_events_and_uncontrolled_images():
    markdown = """# Safe title

<script>alert('x')</script>

<img src=x onerror=alert(1)>

![inline](data:image/png;base64,AAAA)

![external](https://tracker.example/image.png)

![owned](media:file-1)
"""

    html = render_report_html(
        title="Report",
        content_md=markdown,
        chart_svgs={},
        media_urls={"file-1": "/api/files/file-1"},
    )

    assert "<script" not in html
    assert "onerror" not in html
    assert "base64" not in html
    assert "tracker.example" not in html
    assert 'src="/api/files/file-1"' in html
    assert 'loading="lazy"' in html
    assert "<style>" in html
    assert "--rk-bg:#f3ece0" in html
    assert "color-scheme:light" in html
    assert 'class="report pal-warm surface-mag"' in html
    assert "/static/report-v1.css" not in html


def test_renderer_injects_only_known_deterministic_chart_svg():
    html = render_report_html(
        title="Report",
        content_md="Before\n\n[[chart:trend]]\n\nAfter\n\n[[chart:missing]]",
        chart_svgs={"trend": '<svg role="img"><text>10</text></svg>'},
        media_urls={},
    )

    assert '<svg role="img"><text>10</text></svg>' in html
    assert "chart:missing" not in html


def test_renderer_places_validated_chart_when_model_omits_marker():
    html = render_report_html(
        title="Report",
        content_md="# 消费概览\n\n本期支出有明显变化。",
        chart_svgs={"daily-spending": '<svg role="img"><text>681</text></svg>'},
        media_urls={},
    )

    assert '<svg role="img"><text>681</text></svg>' in html


def test_identical_render_input_produces_identical_html():
    kwargs = {
        "title": "Stable",
        "content_md": "# Heading\n\nBody",
        "chart_svgs": {},
        "media_urls": {},
    }
    assert render_report_html(**kwargs) == render_report_html(**kwargs)


def test_pending_illustration_reserves_one_trusted_slot():
    rendered = render_report_presentation(
        title="Pending report",
        content_md="Readable body",
        chart_svgs={},
        media_urls={},
        illustration_status="pending",
    )

    assert rendered.html.count('id="reka-report-illustration"') == 1
    assert 'data-illustration-status="pending"' in rendered.html
    assert "r-illustration-placeholder" in rendered.html
    assert "Readable body" in rendered.html
