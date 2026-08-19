"""Shared contract-test auth helpers (new verification-code flow)."""
from httpx import AsyncClient

from app.auth.email_sender import get_verification_sender


async def register_user(
    client: AsyncClient,
    email: str,
    password: str = "Secret123!",
) -> dict:
    """Request a registration code, then verify + register. Returns response JSON."""
    code_response = await client.post(
        "/api/auth/verification-codes",
        json={"email": email, "purpose": "register"},
    )
    assert code_response.status_code == 200, code_response.text

    sender = get_verification_sender()
    normalized = email.strip().lower()
    code = None
    for item in reversed(sender.sent):
        if item["email"] == normalized:
            code = item["code"]
            break
    assert code is not None, f"no code sent to {normalized}"

    response = await client.post(
        "/api/auth/register",
        json={
            "email": email,
            "verification_code": code,
            "password": password,
            "terms_version": "2026-08-v1",
            "terms_accepted": True,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()
