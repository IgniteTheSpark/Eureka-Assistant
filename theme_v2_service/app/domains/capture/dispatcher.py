from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from app.domains.capture.json_output import extract_json_object


FlashOperation = Literal["create", "query", "update", "delete", "answer"]


class FlashIntent(BaseModel):
    type: str = Field(min_length=1, max_length=100)
    operation: FlashOperation = "create"
    source_text: str = Field(min_length=1, max_length=4000)
    domain: str | None = Field(default=None, max_length=100)
    ordinal: int = Field(default=0, ge=0)
    intent_id: str = Field(default="", max_length=100)
    target_id: str | None = Field(default=None, max_length=100)
    target_query: str | None = Field(default=None, max_length=500)
    contact_patch: dict[str, Any] = Field(default_factory=dict)
    custom_skill_id: str | None = Field(default=None, max_length=100)
    routing_error: str | None = Field(default=None, max_length=100)


class FlashDispatchResult(BaseModel):
    intents: list[FlashIntent] = Field(default_factory=list, max_length=20)


def decode_dispatcher_output(
    content: str,
    *,
    fallback_text: str,
) -> list[FlashIntent]:
    payload = extract_json_object(content)
    raw_intents = payload.get("intents") if payload is not None else None
    if raw_intents is None and payload is not None:
        raw_intents = payload.get("intent_list")

    intents: list[FlashIntent] = []
    if isinstance(raw_intents, list):
        for raw in raw_intents[:20]:
            try:
                intents.append(FlashIntent.model_validate(raw))
            except (TypeError, ValueError):
                continue
    if intents:
        return intents

    fallback = fallback_text.strip()
    if not fallback:
        return []
    return [FlashIntent(type="notes", source_text=fallback)]


def build_dispatcher_messages(
    *,
    transcript: str,
    reference_datetime: str,
    custom_skills: list[dict],
) -> list[dict[str, str]]:
    from app.domains.capture.skill_factory import make_dispatcher_agent

    instruction = make_dispatcher_agent(custom_skills).instruction
    return [
        {"role": "system", "content": instruction},
        {
            "role": "user",
            "content": (
                f"reference_datetime={reference_datetime}\n"
                "BEGIN_UNTRUSTED_TRANSCRIPT\n"
                f"{transcript}\n"
                "END_UNTRUSTED_TRANSCRIPT"
            ),
        },
    ]
