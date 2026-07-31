from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Iterable

import qrcode
from PIL import Image, ImageDraw, ImageFont, ImageOps

from app.config import get_settings
from app.domains.reports.schemas import ShareCardSpec


CARD_SIZE = (1080, 1440)


@dataclass(frozen=True)
class RenderedShareCard:
    png_bytes: bytes
    qr_payload: str
    used_illustration: bool


def share_card_font_errors() -> list[str]:
    settings = get_settings()
    errors = []
    if not Path(settings.share_card_geist_font_path).is_file():
        errors.append("Geist share-card font is unavailable")
    if not Path(settings.share_card_geist_bold_font_path).is_file():
        errors.append("Geist bold share-card font is unavailable")
    if not Path(settings.share_card_noto_cjk_font_path).is_file():
        errors.append("Noto CJK share-card font is unavailable")
    return errors


def _has_cjk(value: str) -> bool:
    return any("\u3400" <= char <= "\u9fff" for char in value)


def _font(value: str, size: int, *, bold: bool = False):
    settings = get_settings()
    if _has_cjk(value):
        path = settings.share_card_noto_cjk_font_path
    elif bold:
        path = settings.share_card_geist_bold_font_path
    else:
        path = settings.share_card_geist_font_path
    return ImageFont.truetype(path, size=size)


def _tokens(value: str) -> list[str]:
    if _has_cjk(value):
        return list(value)
    words = value.split()
    return [word + (" " if index < len(words) - 1 else "") for index, word in enumerate(words)]


def _wrap(draw: ImageDraw.ImageDraw, value: str, font, width: int) -> list[str]:
    lines = []
    current = ""
    for token in _tokens(value):
        candidate = current + token
        if current and draw.textlength(candidate, font=font) > width:
            lines.append(current.rstrip())
            current = token.lstrip()
        else:
            current = candidate
    if current:
        lines.append(current.rstrip())
    return lines or [""]


def _copy(spec: ShareCardSpec) -> str:
    return " ".join(
        [
            spec.headline,
            spec.summary,
            *spec.highlights,
            spec.time_range,
        ]
    )


def _qr_image(public_url: str) -> Image.Image:
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=8,
        border=2,
    )
    qr.add_data(public_url)
    qr.make(fit=True)
    return qr.make_image(fill_color="#26383D", back_color="#F7F5EF").convert(
        "RGB"
    )


def render_share_card(
    spec: ShareCardSpec,
    *,
    public_url: str,
    illustration_bytes: bytes | None = None,
    forbidden_ids: Iterable[str] = (),
) -> RenderedShareCard:
    spec = ShareCardSpec.model_validate(spec)
    copy = _copy(spec)
    if any(internal_id and internal_id in copy for internal_id in forbidden_ids):
        raise ValueError("share-card copy contains an internal identifier")
    font_errors = share_card_font_errors()
    if font_errors:
        raise RuntimeError("; ".join(font_errors))

    image = Image.new("RGB", CARD_SIZE, "#F7F5EF")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((48, 48, 1032, 1392), radius=36, fill="#FBFAF6")
    draw.text((92, 86), "EUREKA / REKA", font=_font("EUREKA", 27, bold=True), fill="#46636B")
    draw.line((92, 138, 988, 138), fill="#D9DEDB", width=2)

    headline_font = _font(spec.headline, 70, bold=True)
    y = 190
    for line in _wrap(draw, spec.headline, headline_font, 860)[:3]:
        draw.text((92, y), line, font=headline_font, fill="#26383D")
        y += 88

    used_illustration = False
    if illustration_bytes:
        try:
            source = Image.open(BytesIO(illustration_bytes)).convert("RGB")
            fitted = ImageOps.fit(source, (896, 280), method=Image.Resampling.LANCZOS)
            mask = Image.new("L", fitted.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                (0, 0, fitted.width, fitted.height), radius=24, fill=255
            )
            image.paste(fitted, (92, y + 14), mask)
            y += 326
            used_illustration = True
        except Exception:
            used_illustration = False
    if not used_illustration:
        draw.rounded_rectangle((92, y + 14, 988, y + 198), radius=24, fill="#E7ECE8")
        draw.ellipse((132, y + 54, 222, y + 144), fill="#B46C4D")
        draw.arc((202, y + 36, 366, y + 164), 205, 510, fill="#46636B", width=12)
        draw.line((390, y + 106, 926, y + 106), fill="#AAB8B5", width=8)
        y += 230

    summary_font = _font(spec.summary, 33)
    for line in _wrap(draw, spec.summary, summary_font, 850)[:4]:
        draw.text((92, y), line, font=summary_font, fill="#53666C")
        y += 48
    y += 28

    highlight_font = _font("".join(spec.highlights), 28, bold=True)
    for index, highlight in enumerate(spec.highlights[:3], start=1):
        draw.rounded_rectangle((92, y, 988, y + 74), radius=18, fill="#F0EEE7")
        draw.text((118, y + 20), f"{index:02d}", font=_font("01", 23, bold=True), fill="#B46C4D")
        draw.text((188, y + 17), highlight, font=highlight_font, fill="#26383D")
        y += 90

    footer_y = 1150
    draw.line((92, footer_y, 988, footer_y), fill="#D9DEDB", width=2)
    draw.text(
        (92, footer_y + 38),
        spec.time_range,
        font=_font(spec.time_range, 27),
        fill="#63757A",
    )
    draw.text(
        (92, footer_y + 94),
        "Open the full report",
        font=_font("Open the full report", 24, bold=True),
        fill="#26383D",
    )
    qr = _qr_image(public_url).resize((190, 190), Image.Resampling.NEAREST)
    image.paste(qr, (798, 1180))

    output = BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return RenderedShareCard(
        png_bytes=output.getvalue(),
        qr_payload=public_url,
        used_illustration=used_illustration,
    )
