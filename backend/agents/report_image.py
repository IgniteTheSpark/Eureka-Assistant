"""§6.6.2 / §6.12 batch 4 — AI imagery (concept illustration / scene backdrop).

HARD RULE (§6.3): AI **never draws data** — no charts, numbers, labels, axes, or
anything readable as data. Real data stays deterministic SVG. AI only draws
illustration / atmosphere; the house-style prompt enforces no-text / no-data /
no-faces.

Model: Nano Banana 2 = `google/gemini-3.1-flash-image-preview` via OpenRouter
(LiteLLM). **Best-effort + graceful**: any error — including this account's
current **403** for gemini ("provider Terms Of Service", see core/llm.py) — →
returns None → the report stays complete, image-less. The pipeline enforces a
per-report cap + a per-user/month quota (no billing; §12 pending).

When a working image key lands, this module produces images with no other change.
"""
import base64
import os
from datetime import datetime, timezone
from typing import Optional

import httpx
import litellm
from sqlalchemy import func, select

from config import settings
from db.database import AsyncSessionLocal
from db.models import File

# Default route (OpenRouter). Overridable per-deploy via settings.image_model —
# e.g. a direct Google AI Studio key uses "gemini/gemini-2.5-flash-image-preview".
_DEFAULT_IMAGE_MODEL = "openrouter/google/gemini-3.1-flash-image-preview"


def _image_model() -> str:
    return (settings.image_model or "").strip() or _DEFAULT_IMAGE_MODEL


def _image_api_key() -> str:
    """Dedicated image key if set, else the primary OpenRouter key (env). Keeps a
    fresh image key isolated from the working DeepSeek text key."""
    return (settings.image_api_key or "").strip() or os.environ.get("OPENROUTER_API_KEY", "")

# Appended to every prompt → consistent on-brand look + the no-data guardrail.
# Verbatim from spec/handoff-report-prompts-v2.md ④a (source of truth — "拿成稿
# 接线,不自拟"). English: image models honor the no-text/no-data constraints
# more reliably in English.
HOUSE_STYLE = (
    "Soft flat editorial illustration. Calm, muted palette that harmonizes with the "
    "report's color theme. Clean negative space, gentle shapes, cohesive on-brand mood. "
    "HARD CONSTRAINTS: absolutely no text, no letters, no numbers, no charts, no graphs, "
    "no UI, no data visualization of any kind, no logos, no watermarks. "
    "No money, no banknotes, no currency, no coins with faces, no printed tickets, no "
    "receipts, no readable labels of any kind (these tempt the model into garbled text). "
    "Objects are blank and unlabeled. Conceptual / atmospheric only. No real human faces."
)

# §6.6.2 — comic/manga style for the data-report/digest SCENE POSTER (the share-y
# 「Eureka Moment」). idea-synthesis/proposal keep the soft-flat HOUSE_STYLE above.
POSTER_STYLE = (
    "Comic / manga ART STYLE on a simple still life of plain everyday objects: bold clean "
    "black ink outlines, flat cel-shading, halftone screentone dots, playful energy, "
    "vibrant cohesive palette, simple background. This is NOT a magazine cover, NOT a "
    "comic-book cover, NOT a poster, NOT a page — just the objects. "
    "HARD CONSTRAINTS (critical): absolutely NO text, NO title, NO words, NO letters, NO "
    "numbers, NO logos, NO brand marks, NO barcodes, NO cover art, NO speech bubbles, NO "
    "labels — EVERY surface is completely blank and unbranded. No charts, no UI, no "
    "watermarks, no money, no tickets, no human faces of any kind."
)

MONTHLY_QUOTA = 30   # AI images / user / month — hard cap (no billing, §12 pending)
PER_REPORT_CAP = 1   # ≤1 AI image per report (§6.6.2)
_SOURCE_TAG = "report_img"


async def monthly_image_count(user_id: str) -> int:
    """AI report-images this user generated this calendar month (for the quota)."""
    now = datetime.now(timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    async with AsyncSessionLocal() as db:
        n = (await db.execute(
            select(func.count(File.id)).where(
                File.user_id == user_id,
                File.source_tag == _SOURCE_TAG,
                File.created_at >= start,
            )
        )).scalar()
    return int(n or 0)


async def quota_ok(user_id: str) -> bool:
    return (await monthly_image_count(user_id)) < MONTHLY_QUOTA


# ── Volcengine Ark (豆包 Seedream) adapter ──────────────────────────────────────
# Ark's images API is OpenAI-images-shaped (POST /images/generations → {data:[{...}]}),
# NOT the gemini multimodal-chat shape litellm uses — so it gets its own thin path.
_ARK_BASE = "https://ark.cn-beijing.volces.com/api/v3"
_ARK_DEFAULT_MODEL = "doubao-seedream-4-5-251128"   # fallback if IMAGE_MODEL unset
_ARK_IMAGE_SIZE = "2K"   # Seedream-4-5 only accepts "2K"/"4K" presets (1K / explicit
                         # small dims → 400). 2K ≈ 0.5-0.9MB base64 inline (reports.html
                         # is MEDIUMTEXT, holds it). Report HTML stays self-contained.


def _is_ark(model: str, api_key: str) -> bool:
    m = (model or "").lower()
    return (m.startswith("doubao") or "seedream" in m or m.startswith("ark/")
            or (api_key or "").startswith("ark-"))


def _data_uri_from_b64(b64: str) -> str:
    """Wrap raw base64 image bytes as a data: URI, sniffing the mime from the
    base64 magic prefix (data:URIs render even with a wrong mime, but be correct)."""
    mime = "image/png"
    if b64.startswith("/9j/"):       mime = "image/jpeg"
    elif b64.startswith("iVBOR"):    mime = "image/png"
    elif b64.startswith("R0lGOD"):   mime = "image/gif"
    elif b64.startswith("UklGR"):    mime = "image/webp"
    return f"data:{mime};base64,{b64}"


async def _generate_ark(prompt: str, model: str, api_key: str) -> Optional[str]:
    """豆包 Seedream → a permanent `data:` URI. Requests b64_json so the image is
    self-contained (Ark `url`s expire ~24h); falls back to downloading a url."""
    payload = {
        "model": model if (_is_ark(model, "") ) else _ARK_DEFAULT_MODEL,
        "prompt": prompt,
        "response_format": "b64_json",
        "size": _ARK_IMAGE_SIZE,
        "sequential_image_generation": "disabled",
        "watermark": False,
        "stream": False,
    }
    async with httpx.AsyncClient(timeout=90) as client:
        r = await client.post(
            f"{_ARK_BASE}/images/generations",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        r.raise_for_status()
        data = (r.json() or {}).get("data") or []
        if not data or not isinstance(data[0], dict):
            return None
        d0 = data[0]
        b64 = d0.get("b64_json")
        if isinstance(b64, str) and b64:
            return _data_uri_from_b64(b64)
        url = d0.get("url")
        if isinstance(url, str) and url.startswith("http"):
            img = await client.get(url)
            img.raise_for_status()
            return _data_uri_from_b64(base64.b64encode(img.content).decode())
    return None


async def generate_image(prompt: str, house_style: Optional[str] = None) -> Optional[str]:
    """One image → a `data:image/...;base64,...` URI, or None on ANY failure
    (403 / timeout / unexpected shape). Never raises. Routes by configured model/
    key: 豆包/Ark → Ark images API; otherwise the gemini-via-litellm path.
    `house_style` selects the look (HOUSE_STYLE soft-flat concept vs POSTER_STYLE
    comic poster); defaults to HOUSE_STYLE."""
    api_key = _image_api_key()
    if not (prompt or "").strip() or not api_key:
        return None
    full_prompt = prompt.strip() + "\n" + (house_style or HOUSE_STYLE)
    model = _image_model()
    try:
        if _is_ark(model, api_key):
            ark_model = model if _is_ark(model, "") else _ARK_DEFAULT_MODEL
            return await _generate_ark(full_prompt, ark_model, api_key)
        r = await litellm.acompletion(
            model=model,
            messages=[{"role": "user", "content": full_prompt}],
            api_key=api_key,
            timeout=45,
        )
        msg = r.choices[0].message
        imgs = getattr(msg, "images", None)
        if imgs:
            i0 = imgs[0]
            url = i0.get("image_url") if isinstance(i0, dict) else getattr(i0, "image_url", None)
            if isinstance(url, dict):
                url = url.get("url")
            if isinstance(url, str) and url.startswith("data:"):
                return url
        return None
    except Exception:
        return None


async def store_image_file(user_id: str, data_uri: str) -> Optional[str]:
    """Persist the image as a File row (source_tag=report_img) → returns file_id
    (used as `asset://<id>`). None on failure."""
    try:
        async with AsyncSessionLocal() as db:
            f = File(user_id=user_id, storage_url=data_uri,
                     file_type="image", source_tag=_SOURCE_TAG)
            db.add(f)
            await db.commit()
            await db.refresh(f)
            return str(f.id)
    except Exception:
        return None
