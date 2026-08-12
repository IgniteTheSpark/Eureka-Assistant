from app.domains.reports.charts import (
    ChartDirective,
    build_default_chart_directives,
    render_chart,
    render_validated_charts,
)


EVIDENCE = {
    "user_evidence": [
        {"payload": {"value": 10}, "asset_id": "asset-1"},
        {"payload": {"value": 15}, "asset_id": "asset-2"},
    ],
    "derived_metrics": {
        "grouped_fields": {
            "effective_date": {
                "2026-08-09": {"numeric_fields": {"amount": {"sum": 140}}},
                "2026-08-10": {"numeric_fields": {"amount": {"sum": 541}}},
            }
        }
    },
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


def test_chart_accepts_server_derived_metrics_and_renders_axis_labels():
    directive = ChartDirective(
        id="daily-spending",
        type="bar",
        title="每日支出",
        series=[
            {
                "label": "支出",
                "labels": ["08-09", "08-10"],
                "source_paths": [
                    "/derived_metrics/grouped_fields/effective_date/2026-08-09/numeric_fields/amount/sum",
                    "/derived_metrics/grouped_fields/effective_date/2026-08-10/numeric_fields/amount/sum",
                ],
                "reducer": "values",
            }
        ],
    )

    result = render_chart(directive, evidence=EVIDENCE)

    assert result.svg is not None
    assert "08-09" in result.svg
    assert "08-10" in result.svg
    assert "140" in result.svg
    assert "541" in result.svg
    assert 'height="0.00"' not in result.svg


def test_default_data_chart_is_built_from_grouped_derived_metrics():
    directives = build_default_chart_directives(
        EVIDENCE,
        template_id="finance_review",
    )

    assert len(directives) == 1
    directive = directives[0]
    assert directive.id == "effective_date-amount-trend"
    assert directive.title == "每日支出"
    assert directive.series[0].label == "支出"
    assert directive.series[0].labels == ["2026-08-09", "2026-08-10"]
    assert all(
        path.startswith("/derived_metrics/grouped_fields/")
        for path in directive.series[0].source_paths
    )
    assert render_chart(directive, evidence=EVIDENCE).svg is not None


def test_data_report_falls_back_when_generator_omits_chart_directives():
    result = render_validated_charts(
        [],
        evidence=EVIDENCE,
        include_default=True,
        template_id="finance_review",
    )

    assert list(result.svgs) == ["effective_date-amount-trend"]
    assert result.warnings == []


def test_default_chart_has_a_valid_stable_id_for_localized_field_names():
    evidence = {
        "derived_metrics": {
            "grouped_fields": {
                "日期": {
                    "周一": {"numeric_fields": {"消费金额": {"sum": 10}}},
                    "周二": {"numeric_fields": {"消费金额": {"sum": 20}}},
                }
            }
        }
    }

    first = build_default_chart_directives(evidence)
    second = build_default_chart_directives(evidence)

    assert first[0].id == second[0].id
    assert first[0].id.startswith("chart-")
