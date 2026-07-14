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

    # §14.9 web-search (briefing genre · 会前调研/外部调研) — a PIPELINE step, not a
    # content-skill tool. Key-driven provider (same pattern as the text LLM):
    # 博查 (api.bochaai.com, China-hosted → reliable 国内 inbound) preferred;
    # Tavily as the dev-box fallback. Both empty → search off, briefing degrades
    # gracefully to a user-data-only report.
    bocha_api_key:      str = ""
    tavily_api_key:     str = ""
    user_id:            str = "default"   # legacy single-tenant fallback (unused once auth is on)
    backend_url:        str = "http://localhost:8000"
    env:                str = "dev"   # dev | prod | staging — drives prod secret enforcement
    demo_reset_enabled: bool = False  # exhibition-only destructive workspace reset

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

    # 闪念文件 ASR — App 创建同事公开服务的 Tencent ASR S3 异步任务，
    # Eureka 只记录 task_id，并轮询公开服务拿识别结果。
    tencent_asr_service_base_url:              str = "https://pre.card.biz"
    flash_asr_provider:                        str = "tencent_asr_s3_async"
    tencent_asr_result_poll_interval_seconds:  int = 5
    tencent_asr_result_poll_timeout_seconds:   int = 300

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()


_DEV_JWT_SECRET = "dev-insecure-change-me"
_MIN_JWT_SECRET_LENGTH = 32


def _jwt_secret_is_weak(secret: str) -> bool:
    value = secret.strip()
    return value == _DEV_JWT_SECRET or len(value) < _MIN_JWT_SECRET_LENGTH


def validate_prod_secrets() -> None:
    """Refuse to boot production or demo-reset mode with insecure secrets.

    Production-like environments require a strong JWT_SECRET and a dedicated
    CONNECTED_APPS_KEY. Exhibition reset additionally requires a strong signing
    secret in every environment because a forgeable token could otherwise reset
    another user's workspace. Reset-disabled local dev keeps its zero-config
    startup behavior.
    """
    is_prod = settings.env.lower() in ("prod", "production", "staging")
    if not is_prod and not settings.demo_reset_enabled:
        return

    problems = []
    if _jwt_secret_is_weak(settings.jwt_secret):
        problems.append(
            f"JWT_SECRET must be at least {_MIN_JWT_SECRET_LENGTH} characters and "
            "must not use the dev default"
        )
    if is_prod and not settings.connected_apps_key.strip():
        problems.append(
            "CONNECTED_APPS_KEY is not set — third-party credentials would encrypt "
            "under a jwt-derived key (predictable). Generate a Fernet key and set it."
        )
    if problems:
        raise RuntimeError(
            "Refusing to start: insecure secrets for production or demo reset:\n  - "
            + "\n  - ".join(problems)
            + "\nSet them in the environment before starting the backend."
        )
