from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_PRODUCTION_SENDER = "verify@mail.ureka.chat"
_EXAMPLE_SECRET_MARKERS = ("replace-with", "example.com")
_JWT_SECRET_MARKERS = ("replace-with", "example", "change-me", "test-secret")


def _is_example_placeholder(value: str) -> bool:
    lowered = value.strip().lower()
    return any(marker in lowered for marker in _EXAMPLE_SECRET_MARKERS)


def _is_unsafe_jwt_secret(value: str) -> bool:
    lowered = value.strip().lower()
    return len(value.encode("utf-8")) < 32 or any(
        marker in lowered for marker in _JWT_SECRET_MARKERS
    )


def _is_absolute_https_url(value: str) -> bool:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        return False
    return not any(char.isspace() for char in value)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "dev"
    api_port: int = 8000
    database_url: str = "mysql://theme_v2:theme_v2@mysql:3306/eureka_theme_v2"
    jwt_secret: str = "dev-insecure-change-me"
    worker_poll_seconds: float = 0.5
    job_lease_seconds: int = 60
    media_root: str = "/data/media"
    default_user_timezone: str = "Asia/Shanghai"
    streaming_asr_enabled: bool = False
    dashscope_api_key: str | None = None
    dashscope_asr_ws_url: str = ""
    ali_asr_model: str = "qwen-audio-3.0-asr-flash-streaming"
    asr_rate_limit_per_minute: int = Field(default=10, ge=1)
    asr_provider_start_timeout_seconds: float = Field(default=8, gt=0)
    asr_provider_send_timeout_seconds: float = Field(default=3, gt=0)
    asr_provider_finalize_timeout_seconds: float = Field(default=10, gt=0)
    asr_provider_cleanup_timeout_seconds: float = Field(default=2, gt=0)
    asr_client_send_timeout_seconds: float = Field(default=2, gt=0)
    tencent_asr_service_base_url: str = "https://pre.card.biz"
    capture_asr_poll_interval_seconds: float = Field(default=5, gt=0)
    capture_asr_poll_timeout_seconds: float = Field(default=1800, gt=0)
    capture_provider_timeout_seconds: float = Field(default=20, gt=0)
    capture_agent_enabled: bool = False
    capture_agent_model: str | None = None
    capture_agent_api_key: str | None = None
    capture_agent_timeout_seconds: float = Field(default=60, gt=0)
    capture_agent_max_attempts: int = Field(default=3, ge=1)
    chat_agent_enabled: bool = False
    chat_agent_model: str | None = None
    chat_agent_api_key: str | None = None
    chat_agent_timeout_seconds: float = Field(default=60, gt=0)
    capture_flash_wait_seconds: float = Field(default=20, gt=0)
    capture_flash_poll_interval_seconds: float = Field(default=0.05, gt=0)
    report_planner_enabled: bool = False
    report_pipeline_enabled: bool = False
    report_planner_model: str | None = None
    report_generator_model: str | None = None
    report_illustration_enabled: bool = False
    report_illustration_model: str | None = None
    report_illustration_api_key: str | None = None
    report_provider_api_key: str | None = None
    report_provider_timeout_seconds: float = 60.0
    report_illustration_timeout_seconds: float = 90.0
    report_optional_illustration_timeout_seconds: float = Field(
        default=30.0,
        gt=0,
    )
    report_provider_max_attempts: int = 3
    report_planning_timeout_seconds: int = 300
    report_generation_timeout_seconds: int = 1800
    report_web_enabled: bool = False
    report_web_model: str = "deepseek-v4-flash"
    report_web_api_url: str = "https://api.deepseek.com"
    report_web_api_key: str | None = None
    report_web_timeout_seconds: float = 20.0
    report_illustration_api_url: str | None = None
    report_public_base_url: str = "http://localhost:8100"
    share_card_geist_font_path: str = (
        "/usr/share/fonts/truetype/geist/Geist-Regular.ttf"
    )
    share_card_geist_bold_font_path: str = (
        "/usr/share/fonts/truetype/geist/Geist-Bold.ttf"
    )
    share_card_noto_cjk_font_path: str = (
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    )

    # --- Email verification (§5.2 / §5.3) ---
    email_provider: str = "mock"  # mock | aliyun_directmail | disabled
    email_fixed_code: str | None = Field(default=None, pattern=r"^\d{6}$")
    email_from_address: str = "noreply@example.com"
    email_from_name: str = "UReka"
    email_code_ttl_seconds: int = 600  # 10 minutes
    email_resend_cooldown_seconds: int = 60
    email_send_per_hour_per_email: int = 5
    email_send_per_day_per_email: int = 20
    email_send_per_hour_per_ip: int = 20
    email_send_per_day_per_ip: int = 100
    email_max_failed_attempts: int = 5
    email_lockout_seconds: int = 900  # 15 minutes
    login_attempts_per_email_15_min: int = Field(default=10, ge=1)
    login_attempts_per_ip_15_min: int = Field(default=50, ge=1)
    # Aliyun DirectMail (production mainland-China provider)
    directmail_access_key_id: str = ""
    directmail_access_key_secret: str = ""
    directmail_account_name: str = ""
    # Legal links / versions (front end pulls via /api/auth/config)
    terms_url: str = ""
    privacy_url: str = ""
    terms_version_current: str = "2026-08-v1"

    @model_validator(mode="after")
    def reject_insecure_prod(self) -> "Settings":
        if self.env in {"prod", "production"}:
            if _is_unsafe_jwt_secret(self.jwt_secret):
                raise ValueError(
                    "JWT_SECRET must be at least 32 UTF-8 bytes and must not "
                    "contain placeholder markers in production"
                )
            if self.email_fixed_code is not None:
                raise ValueError("EMAIL_FIXED_CODE is forbidden in production")
            if self.email_provider != "aliyun_directmail":
                raise ValueError("EMAIL_PROVIDER must be aliyun_directmail in production")
            if self.email_from_address.strip() != _PRODUCTION_SENDER:
                raise ValueError(
                    f"EMAIL_FROM_ADDRESS must be {_PRODUCTION_SENDER!r} in production"
                )
            if self.directmail_account_name.strip() != _PRODUCTION_SENDER:
                raise ValueError(
                    f"DIRECTMAIL_ACCOUNT_NAME must be {_PRODUCTION_SENDER!r} in production"
                )
            if not self.directmail_access_key_id.strip():
                raise ValueError("DIRECTMAIL_ACCESS_KEY_ID is required in production")
            if _is_example_placeholder(self.directmail_access_key_id):
                raise ValueError(
                    "DIRECTMAIL_ACCESS_KEY_ID must not be an example placeholder in production"
                )
            if not self.directmail_access_key_secret.strip():
                raise ValueError("DIRECTMAIL_ACCESS_KEY_SECRET is required in production")
            if _is_example_placeholder(self.directmail_access_key_secret):
                raise ValueError(
                    "DIRECTMAIL_ACCESS_KEY_SECRET must not be an example placeholder in production"
                )
            if not _is_absolute_https_url(self.terms_url):
                raise ValueError("TERMS_URL must be an absolute HTTPS URL in production")
            if not _is_absolute_https_url(self.privacy_url):
                raise ValueError("PRIVACY_URL must be an absolute HTTPS URL in production")
            if not self.terms_version_current.strip():
                raise ValueError("TERMS_VERSION_CURRENT is required in production")
        return self

    def provider_readiness_errors(self) -> list[str]:
        errors = []
        errors.extend(self.asr_readiness_errors())
        if self.report_planner_enabled and not self.report_planner_model:
            errors.append("REPORT_PLANNER_MODEL is required")
        if self.report_pipeline_enabled and not self.report_generator_model:
            errors.append("REPORT_GENERATOR_MODEL is required")
        if (
            self.report_planner_enabled or self.report_pipeline_enabled
        ) and not self.report_provider_api_key:
            errors.append("REPORT_PROVIDER_API_KEY is required")
        if self.report_web_enabled:
            if not self.report_web_api_key_value():
                errors.append(
                    "REPORT_WEB_API_KEY or REPORT_PROVIDER_API_KEY is required"
                )
            parsed = urlparse(self.report_web_api_url)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                errors.append(
                    "REPORT_WEB_API_URL must be an absolute HTTP(S) URL"
                )
            if not self.report_web_model.strip():
                errors.append("REPORT_WEB_MODEL is required")
        if self.report_illustration_enabled:
            if not self.report_illustration_model:
                errors.append("REPORT_ILLUSTRATION_MODEL is required")
            if not self.report_illustration_api_url:
                errors.append("REPORT_ILLUSTRATION_API_URL is required")
            if not self.report_illustration_api_key:
                errors.append("REPORT_ILLUSTRATION_API_KEY is required")
            if self.report_illustration_api_url:
                parsed = urlparse(self.report_illustration_api_url)
                if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                    errors.append(
                        "REPORT_ILLUSTRATION_API_URL must be an absolute HTTP(S) URL"
                    )
        if self.capture_agent_enabled and not self.capture_agent_model:
            errors.append("CAPTURE_AGENT_MODEL is required")
        if self.chat_agent_enabled and not self.chat_agent_model:
            errors.append("CHAT_AGENT_MODEL is required")
        return errors

    def asr_readiness_errors(self) -> list[str]:
        if not self.streaming_asr_enabled:
            return []
        errors: list[str] = []
        if not (self.dashscope_api_key or "").strip():
            errors.append("DASHSCOPE_API_KEY is required")
        parsed = urlparse(self.dashscope_asr_ws_url.strip())
        if (
            parsed.scheme != "wss"
            or not parsed.hostname
            or not parsed.hostname.endswith(".maas.aliyuncs.com")
            or parsed.path != "/api-ws/v1/inference"
            or parsed.query
            or parsed.fragment
        ):
            errors.append(
                "DASHSCOPE_ASR_WS_URL must be a secure workspace WebSocket "
                "ending in /api-ws/v1/inference"
            )
        if self.ali_asr_model != "qwen-audio-3.0-asr-flash-streaming":
            errors.append(
                "ALI_ASR_MODEL must be qwen-audio-3.0-asr-flash-streaming"
            )
        return errors

    def validate_asr(self) -> None:
        errors = self.asr_readiness_errors()
        if not self.streaming_asr_enabled:
            raise RuntimeError("streaming ASR is disabled")
        if errors:
            raise RuntimeError("; ".join(errors))

    def report_planner_available(self) -> bool:
        return self.env == "test" or bool(
            self.report_planner_enabled and self.report_planner_model
        )

    def report_pipeline_available(self) -> bool:
        return self.env == "test" or bool(
            self.report_pipeline_enabled and self.report_generator_model
        )

    def report_web_api_key_value(self) -> str | None:
        return self.report_web_api_key or self.report_provider_api_key

    def report_web_available(self) -> bool:
        parsed = urlparse(self.report_web_api_url)
        return bool(
            self.report_web_enabled
            and self.report_web_model.strip()
            and self.report_web_api_key_value()
            and parsed.scheme in {"http", "https"}
            and parsed.netloc
        )

    def report_illustration_available(self) -> bool:
        if not self.report_illustration_api_url:
            return False
        parsed = urlparse(self.report_illustration_api_url)
        return bool(
            self.report_illustration_enabled
            and self.report_illustration_model
            and self.report_illustration_api_key
            and parsed.scheme in {"http", "https"}
            and parsed.netloc
        )

    def runtime_readiness_errors(self) -> list[str]:
        errors = self.provider_readiness_errors()
        if not Path(self.share_card_geist_font_path).is_file():
            errors.append("Geist share-card font is unavailable")
        if not Path(self.share_card_geist_bold_font_path).is_file():
            errors.append("Geist bold share-card font is unavailable")
        if not Path(self.share_card_noto_cjk_font_path).is_file():
            errors.append("Noto CJK share-card font is unavailable")
        return errors


@lru_cache
def get_settings() -> Settings:
    return Settings()
