from io import BytesIO

import pytest
from PIL import Image
from pydantic import ValidationError

from app.domains.reports.schemas import ShareCardSpec
from app.domains.reports.share_cards import render_share_card


def _spec() -> ShareCardSpec:
    return ShareCardSpec(
        headline="七月阶段复盘",
        summary="把本月的重要变化整理成一张可以快速理解的卡片。",
        highlights=["节奏更稳定", "完成关键复盘", "下一步更清晰"],
        time_range="2026 年 7 月",
    )


def test_card_is_exact_deterministic_png_with_current_share_qr():
    first = render_share_card(
        _spec(),
        public_url="https://reports.example/r/current-token",
    )
    second = render_share_card(
        _spec(),
        public_url="https://reports.example/r/current-token",
    )
    image = Image.open(BytesIO(first.png_bytes))

    assert image.size == (1080, 1440)
    assert image.format == "PNG"
    assert first.png_bytes == second.png_bytes
    assert first.qr_payload == "https://reports.example/r/current-token"
    assert first.used_illustration is False


def test_share_card_has_three_highlight_limit_and_rejects_internal_ids():
    with pytest.raises(ValidationError):
        ShareCardSpec(
            headline="Too many",
            summary="Summary",
            highlights=["1", "2", "3", "4"],
            time_range="July",
        )
    with pytest.raises(ValueError, match="internal identifier"):
        render_share_card(
            _spec().model_copy(update={"summary": "asset-private-id"}),
            public_url="https://reports.example/r/token",
            forbidden_ids={"asset-private-id"},
        )


def test_png_metadata_contains_no_internal_ids():
    rendered = render_share_card(
        _spec(),
        public_url="https://reports.example/r/token",
        forbidden_ids={"asset-private-id", "run-private-id"},
    )
    image = Image.open(BytesIO(rendered.png_bytes))

    assert "asset-private-id" not in str(image.info)
    assert "run-private-id" not in str(image.info)
