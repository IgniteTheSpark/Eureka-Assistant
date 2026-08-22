"""Authenticated mobile voice-input WebSocket endpoint."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from typing import Any

from fastapi import APIRouter, WebSocket

from core.asr.streaming import StreamingAsrGateway


router = APIRouter()
_gateway = StreamingAsrGateway()


def authenticate_websocket(
    headers: Mapping[str, str],
    *,
    token_decoder: Callable[[str], dict[str, Any] | None] | None = None,
) -> str | None:
    authorization = headers.get("authorization") or headers.get("Authorization") or ""
    if not authorization.startswith("Bearer "):
        return None
    token = authorization[len("Bearer ") :].strip()
    if not token:
        return None
    if token_decoder is None:
        from core.security import decode_token

        token_decoder = decode_token
    payload = token_decoder(token)
    subject = payload.get("sub") if isinstance(payload, dict) else None
    return str(subject) if subject else None


async def serve_asr_websocket(
    websocket: Any,
    *,
    gateway: StreamingAsrGateway | None = None,
    token_decoder: Callable[[str], dict[str, Any] | None] | None = None,
) -> None:
    user_id = authenticate_websocket(
        websocket.headers, token_decoder=token_decoder
    )
    if user_id is None:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    await (gateway or _gateway).handle(websocket, user_id=user_id)


@router.websocket("/asr/stream")
async def asr_stream(websocket: WebSocket) -> None:
    await serve_asr_websocket(websocket)
