from types import SimpleNamespace

from app.domains.reports.evidence_options import _asset_card_text


def test_baseline_asset_without_render_spec_uses_payload_title() -> None:
    asset = SimpleNamespace(
        payload_json={
            "title": "明天下午提交周报",
            "content": "整理本周进展和风险",
        }
    )
    skill = SimpleNamespace(
        render_spec_json={},
        display_name="待办",
        machine_name="todo",
    )

    title, subtitle = _asset_card_text(asset, skill)

    assert title == "明天下午提交周报"
    assert subtitle == "整理本周进展和风险"


def test_asset_without_text_payload_falls_back_to_skill_name() -> None:
    asset = SimpleNamespace(payload_json={"amount": 28.5})
    skill = SimpleNamespace(
        render_spec_json={},
        display_name="消费",
        machine_name="expense",
    )

    title, subtitle = _asset_card_text(asset, skill)

    assert title == "28.5"
    assert subtitle == "消费"
