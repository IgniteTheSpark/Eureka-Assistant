from functools import lru_cache

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

    @model_validator(mode="after")
    def reject_insecure_prod(self) -> "Settings":
        if self.env in {"prod", "production"} and self.jwt_secret == "dev-insecure-change-me":
            raise ValueError("JWT_SECRET must be changed in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
