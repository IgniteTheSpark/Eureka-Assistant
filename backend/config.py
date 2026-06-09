from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url:       str = "mysql://eureka:eureka@localhost:3306/eureka"
    # Primary LLM — DeepSeek direct API (api.deepseek.com, China-hosted → reliable
    # 国内 inbound; OpenAI-compatible, native litellm `deepseek/` provider).
    deepseek_api_key:   str = ""
    # Legacy LLM gateway. No longer the text-model path (replaced by deepseek_api_key
    # for 国内 inbound); still the fallback key for the §6.6.2 gemini image path.
    openrouter_api_key: str = ""
    openai_api_key:     str = ""   # Whisper ASR (audio path deferred)

    # §6.6.2 AI 配图 — OPTIONAL dedicated image key/model. Lets a fresh image key
    # land WITHOUT touching the working DeepSeek text key (which is on a
    # gemini/claude/gpt-TOS-blocked account). Both empty → falls back to
    # openrouter_api_key + the default OpenRouter gemini-image model.
    #   • New OpenRouter key (clean account): set image_api_key only.
    #   • Direct Google AI Studio key:        set image_api_key AND
    #     image_model="gemini/gemini-2.5-flash-image-preview".
    image_api_key:      str = ""
    image_model:        str = ""
    user_id:            str = "default"   # legacy single-tenant fallback (unused once auth is on)
    backend_url:        str = "http://localhost:8000"
    env:                str = "dev"   # dev | prod | staging — drives prod secret enforcement

    # Auth (email+password → HS256 token). MUST be overridden in prod via env
    # (JWT_SECRET); the default is dev-only and not safe to ship.
    jwt_secret:        str = "dev-insecure-change-me"
    jwt_expire_hours:  int = 720          # 30d — long-lived for a TestFlight beta

    # Connected Apps (§1.7.1): symmetric key for encrypting per-user external
    # credentials at rest. Set CONNECTED_APPS_KEY in prod (a Fernet key, i.e.
    # urlsafe-base64 32 bytes). Empty → derived from jwt_secret (dev-only).
    connected_apps_key: str = ""

    # §13.1 / B1 — 百智 (100wiser) OAuth login. 百智 is the IdP; Eureka still mints
    # its own HS256 session token (§3 unchanged). app_id/secret/name come from the
    # 百智 console → set in .env.prod ONLY (app_secret NEVER leaves the backend).
    # Blank app_id → the 百智 login endpoints report "未配置" (503); email login is
    # unaffected. baizhi_me_url is OPTIONAL: the authoritative "current user"
    # endpoint for a stable id; when blank we derive the id from the real-token JWT.
    baizhi_base_url:       str = "https://openapi.100wiser.com"   # API host (token exchange)
    baizhi_oauth_base_url: str = "https://100wiser.com"           # OAuth bridge host
    baizhi_app_id:         str = ""
    baizhi_app_secret:     str = ""
    baizhi_app_name:       str = ""
    baizhi_redirect_url:   str = ""   # = 百智 console redirectUrl (this backend's /auth/baizhi/callback)
    baizhi_me_url:         str = ""   # OPTIONAL authoritative "current user" endpoint (Bearer real-token)
    eureka_app_scheme:     str = "eureka"   # deep-link scheme back to the Flutter app

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()


def validate_prod_secrets() -> None:
    """Refuse to boot a production-like deployment with dev secrets (codex P1.2).

    Production-like = `ENV` is prod/staging, OR `JWT_SECRET` was overridden from
    the dev default (a real deploy always overrides it). In that case both a
    strong JWT_SECRET and a dedicated CONNECTED_APPS_KEY are mandatory — without
    the latter, per-user third-party credentials would be encrypted under a key
    *derived from* jwt_secret (see core/crypto.py), i.e. predictable. Call at
    startup so a misconfigured prod fails fast instead of silently degrading.
    """
    is_prod = (
        settings.env.lower() in ("prod", "production", "staging")
        or settings.jwt_secret != "dev-insecure-change-me"
    )
    if not is_prod:
        return
    problems = []
    if settings.jwt_secret == "dev-insecure-change-me":
        problems.append("JWT_SECRET is still the dev default — set a strong secret")
    if not settings.connected_apps_key.strip():
        problems.append(
            "CONNECTED_APPS_KEY is not set — third-party credentials would encrypt "
            "under a jwt-derived key (predictable). Generate a Fernet key and set it."
        )
    if problems:
        raise RuntimeError(
            "Refusing to start: production-like environment with insecure secrets:\n  - "
            + "\n  - ".join(problems)
            + "\nSet them in the environment (e.g. .env.prod) before deploying."
        )
