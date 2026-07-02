from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Anthropic
    anthropic_api_key: str
    claude_model: str = "claude-sonnet-4-5"

    # Supabase
    supabase_url: str
    supabase_service_role_key: str

    # Upstash Redis
    upstash_redis_rest_url: str
    upstash_redis_rest_token: str

    # OpenAI (Whisper)
    openai_api_key: str

    # Stripe
    stripe_secret_key: str
    stripe_webhook_secret: str

    # App
    flutter_app_origin: str = "http://localhost:3000"
    environment: str = "development"


@lru_cache
def get_settings() -> Settings:
    return Settings()
