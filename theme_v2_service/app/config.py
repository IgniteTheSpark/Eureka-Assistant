from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


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

    @model_validator(mode="after")
    def reject_insecure_prod(self) -> "Settings":
        if self.env in {"prod", "production"} and self.jwt_secret == "dev-insecure-change-me":
            raise ValueError("JWT_SECRET must be changed in production")
        return self

    def provider_readiness_errors(self) -> list[str]:
        errors = []
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
