import json
import os
from pathlib import Path
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/sepsisnet"
    model_config_path: str = str(
        Path(__file__).resolve().parents[3] / "models" / "tier2_supermodel_v1.json"
    )
    scoring_min_hours: float = 6.0
    scoring_threshold: str = "youden"
    host: str = "0.0.0.0"
    port: int = 8000

    model_config = {"env_prefix": "SEPSISNET_"}


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def load_model_config() -> dict:
    path = get_settings().model_config_path
    with open(path) as f:
        return json.load(f)
