from app.domains.reports.rendering import (
    generate_optional_illustration,
    render_report_html,
)


class FailingIllustrationProvider:
    def __init__(self):
        self.prompts = []

    async def generate(self, prompt):
        self.prompts.append(prompt)
        raise RuntimeError("provider unavailable")


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
    assert "--paper: #f7f5ef" in html
    assert "color-scheme: light dark" in html
    assert "@media (prefers-color-scheme: dark)" in html
    assert "--ink: #f5f7fa" in html
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


def test_identical_render_input_produces_identical_html():
    kwargs = {
        "title": "Stable",
        "content_md": "# Heading\n\nBody",
        "chart_svgs": {},
        "media_urls": {},
    }
    assert render_report_html(**kwargs) == render_report_html(**kwargs)


async def test_illustration_failure_degrades_and_keeps_rendering():
    provider = FailingIllustrationProvider()

    outcome = await generate_optional_illustration(
        policy="optional",
        prompt="calm chart with text 42",
        provider=provider,
        store_image=None,
    )

    assert outcome.execution.status == "failed_degraded"
    assert outcome.file_id is None
    assert outcome.warnings == ["illustration generation failed"]
    assert "chart" not in provider.prompts[0].casefold()
    assert "text" not in provider.prompts[0].casefold()
    assert "42" not in provider.prompts[0]
