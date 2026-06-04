from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url:       str = "mysql://eureka:eureka@localhost:3306/eureka"
    openrouter_api_key: str = ""   # Primary LLM gateway (current model: moonshotai/kimi-k2.5)
    openai_api_key:     str = ""   # Whisper ASR (audio path deferred)
    user_id:            str = "default"   # legacy single-tenant fallback (unused once auth is on)
    backend_url:        str = "http://localhost:8000"

    # Auth (email+password → HS256 token). MUST be overridden in prod via env
    # (JWT_SECRET); the default is dev-only and not safe to ship.
    jwt_secret:        str = "dev-insecure-change-me"
    jwt_expire_hours:  int = 720          # 30d — long-lived for a TestFlight beta

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
