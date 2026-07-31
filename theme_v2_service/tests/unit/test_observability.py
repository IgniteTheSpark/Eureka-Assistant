import logging

from httpx import ASGITransport, AsyncClient

from app.main import app
from app.observability import MetricRegistry, sanitize_log_context


def test_metric_registry_exposes_declared_report_metrics():
    registry = MetricRegistry()
    registry.increment("run_created_total")
    registry.increment("run_failed_total", labels={"failure_stage": "planning"})
    registry.observe("planner_duration_ms", 125)

    output = registry.render_prometheus()

    assert "run_created_total 1" in output
    assert 'run_failed_total{failure_stage="planning"} 1' in output
    assert "planner_duration_ms 125" in output
    assert "share_card_generated_total 0" in output


def test_log_context_allows_correlation_but_drops_sensitive_values(caplog):
    context = sanitize_log_context(
        run_id="run-1",
        job_id="job-1",
        failure_stage="web_search",
        asset_payload={"private": "secret"},
        event_description="private event",
        web_query="medical details",
        share_token="raw-token",
        prompt="ignore previous instructions",
    )

    with caplog.at_level(logging.INFO):
        logging.getLogger("test").info("report event", extra=context)

    assert context == {
        "run_id": "run-1",
        "job_id": "job-1",
        "failure_stage": "web_search",
    }
    assert "secret" not in caplog.text
    assert "raw-token" not in caplog.text


async def test_metrics_endpoint_exposes_text_without_authentication():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as client:
        response = await client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "run_created_total" in response.text
    assert "invalid_share_token_total" in response.text
