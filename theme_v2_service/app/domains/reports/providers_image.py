import base64
import re
from urllib.parse import urlparse

import httpx

from app.domains.reports.providers import (
    GeneratedImage,
    PermanentProviderError,
    RetryableProviderError,
)


FORBIDDEN_ILLUSTRATION_TERMS = (
    "chart",
    "graph",
    "diagram",
    "axis",
    "label",
    "text",
    "number",
    "logo",
    "图表",
    "坐标",
    "文字",
    "数字",
    "标志",
)


def sanitize_illustration_prompt(
    prompt: str,
    *,
    sensitive_values: list[str] | None = None,
) -> str:
    sanitized = prompt
    for value in sorted(
        {item.strip() for item in sensitive_values or [] if item.strip()},
        key=len,
        reverse=True,
    ):
        sanitized = sanitized.replace(value, " ")
    for term in FORBIDDEN_ILLUSTRATION_TERMS:
        sanitized = re.sub(re.escape(term), " ", sanitized, flags=re.IGNORECASE)
    sanitized = re.sub(r"\d+(?:\.\d+)?", " ", sanitized)
    return " ".join(sanitized.split())[:1000]


class OpenAICompatibleIllustrationProvider:
    def __init__(
        self,
        *,
        client: httpx.AsyncClient,
        endpoint: str,
        api_key: str,
        model: str,
        timeout_seconds: float,
    ) -> None:
        self.client = client
        self.endpoint = endpoint
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds

    async def generate(self, prompt: str) -> GeneratedImage:
        sanitized = sanitize_illustration_prompt(prompt)
        if not sanitized:
            raise PermanentProviderError("illustration prompt is empty after sanitization")
        try:
            response = await self.client.post(
                self.endpoint,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "prompt": sanitized,
                    "response_format": "b64_json",
                },
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
        except httpx.TimeoutException as exc:
            raise RetryableProviderError("illustration provider timed out") from exc
        except httpx.HTTPStatusError as exc:
            error = (
                RetryableProviderError
                if exc.response.status_code >= 500
                else PermanentProviderError
            )
            raise error("illustration provider rejected the request") from exc
        content_type = response.headers.get("content-type", "").split(";", 1)[0]
        if content_type.startswith("image/"):
            return GeneratedImage(data=response.content, mime_type=content_type)
        try:
            payload = response.json()
            item = payload["data"][0]
            if "b64_json" in item:
                data = base64.b64decode(item["b64_json"], validate=True)
                mime_type = item.get("mime_type", "image/png")
                if not mime_type.startswith("image/"):
                    raise PermanentProviderError("provider returned non-image MIME type")
                return GeneratedImage(data=data, mime_type=mime_type)
            image_url = item.get("url")
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise PermanentProviderError("provider returned invalid image data") from exc
        if not image_url or urlparse(image_url).scheme not in {"http", "https"}:
            raise PermanentProviderError("provider returned invalid image URL")
        try:
            image_response = await self.client.get(
                image_url,
                timeout=self.timeout_seconds,
            )
            image_response.raise_for_status()
        except httpx.HTTPError as exc:
            raise RetryableProviderError("generated image download failed") from exc
        mime_type = image_response.headers.get("content-type", "").split(";", 1)[0]
        if not mime_type.startswith("image/"):
            raise PermanentProviderError("provider returned non-image MIME type")
        return GeneratedImage(data=image_response.content, mime_type=mime_type)
