from __future__ import annotations

from collections.abc import Callable, Mapping
from typing import Any

from fastapi import APIRouter, WebSocket

from app.auth.security import decode_token
from app.domains.asr.streaming import StreamingAsrGateway


router = APIRouter(prefix="/api", tags=["asr"])
_gateway = StreamingAsrGateway()


def authenticate_websocket(
    headers: Mapping[str, str],
    *,
    token_decoder: Callable[[str], dict[str, Any] | None] = decode_token,
) -> str | None:
    authorization = headers.get("authorization") or headers.get("Authorization") or ""
    if not authorization.startswith("Bearer "):
        return None
    token = authorization[len("Bearer ") :].strip()
    if not token:
        return None
    payload = token_decoder(token)
    subject = payload.get("sub") if isinstance(payload, dict) else None
    return str(subject) if subject else None


async def serve_asr_websocket(
    websocket: Any,
    *,
    gateway: StreamingAsrGateway | None = None,
    token_decoder: Callable[[str], dict[str, Any] | None] = decode_token,
) -> None:
    user_id = authenticate_websocket(websocket.headers, token_decoder=token_decoder)
    if user_id is None:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    await (gateway or _gateway).handle(websocket, user_id=user_id)


@router.websocket("/asr/stream")
async def asr_stream(websocket: WebSocket) -> None:
    await serve_asr_websocket(websocket)
