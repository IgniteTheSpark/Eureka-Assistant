from fastapi import HTTPException, Request

from app.auth.security import decode_token


def get_current_user_id(request: Request) -> str:
    value = request.headers.get("Authorization", "")
    if value.startswith("Bearer "):
        payload = decode_token(value[7:].strip())
        if payload and payload.get("sub"):
            return str(payload["sub"])
    raise HTTPException(status_code=401, detail="未登录或登录已过期")
