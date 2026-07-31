from functools import lru_cache
from pathlib import Path

from pydantic import model_validator
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
    report_planner_enabled: bool = False
    report_pipeline_enabled: bool = False
    report_planner_model: str | None = None
    report_generator_model: str | None = None
    report_illustration_model: str | None = None
    report_provider_api_key: str | None = None
    report_provider_timeout_seconds: float = 60.0
    report_provider_max_attempts: int = 3
    report_web_timeout_seconds: float = 20.0
    bocha_api_key: str | None = None
    bocha_api_url: str = "https://api.bochaai.com/v1/web-search"
    tavily_api_key: str | None = None
    tavily_api_url: str = "https://api.tavily.com/search"
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
        return errors

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
