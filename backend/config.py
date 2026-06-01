from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url:       str = "postgresql://eureka:eureka@localhost:5432/eureka"
    openrouter_api_key: str = ""   # Primary LLM gateway (current model: moonshotai/kimi-k2.5)
    openai_api_key:     str = ""   # Whisper ASR (audio path deferred)
    user_id:            str = "default"
    backend_url:        str = "http://localhost:8000"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
