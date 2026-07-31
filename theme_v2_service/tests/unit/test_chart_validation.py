from app.domains.reports.charts import ChartDirective, render_chart


EVIDENCE = {
    "user_evidence": [
        {"payload": {"value": 10}, "asset_id": "asset-1"},
        {"payload": {"value": 15}, "asset_id": "asset-2"},
    ]
}


def test_chart_values_are_resolved_only_from_evidence_paths():
    directive = ChartDirective(
        id="trend",
        type="line",
        title="Recorded values",
        series=[
            {
                "label": "Value",
                "source_paths": [
                    "/user_evidence/0/payload/value",
                    "/user_evidence/1/payload/value",
                ],
                "reducer": "values",
            }
        ],
    )

    first = render_chart(directive, evidence=EVIDENCE)
    second = render_chart(directive, evidence=EVIDENCE)

    assert first.svg == second.svg
    assert first.warnings == []
    assert "10" in first.svg and "15" in first.svg
    assert "<svg" in first.svg


def test_invalid_or_non_numeric_source_removes_chart_with_warning():
    directive = ChartDirective(
        id="invalid",
        type="bar",
        title="Invalid",
        series=[
            {
                "label": "Invented",
                "source_paths": ["/user_evidence/9/payload/value"],
                "reducer": "values",
            }
        ],
    )

    result = render_chart(directive, evidence=EVIDENCE)

    assert result.svg is None
    assert result.warnings == ["chart invalid: unavailable evidence source"]


def test_summary_chart_uses_registered_pure_reducer():
    directive = ChartDirective(
        id="average",
        type="summary",
        title="Average",
        series=[
            {
                "label": "Average",
                "source_paths": [
                    "/user_evidence/0/payload/value",
                    "/user_evidence/1/payload/value",
                ],
                "reducer": "average",
            }
        ],
    )

    result = render_chart(directive, evidence=EVIDENCE)

    assert result.svg is not None
    assert "12.5" in result.svg


def test_chart_api_has_no_image_provider_path():
    assert "image" not in render_chart.__annotations__
    assert "provider" not in render_chart.__annotations__
