"""Upstash Redis cache helpers via REST API (httpx async)."""

import json
from typing import Any

import httpx

from config import get_settings

_client: httpx.AsyncClient | None = None


async def init_redis_client() -> None:
    global _client
    settings = get_settings()
    _client = httpx.AsyncClient(
        base_url=settings.upstash_redis_rest_url,
        headers={"Authorization": f"Bearer {settings.upstash_redis_rest_token}"},
        timeout=httpx.Timeout(10.0),
    )


async def close_redis_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


def get_client() -> httpx.AsyncClient:
    if _client is None:
        raise RuntimeError("Redis client not initialized. Call init_redis_client() in app lifespan.")
    return _client


async def cache_set(key: str, value: Any, ex_seconds: int | None = None) -> None:
    client = get_client()
    payload = value if isinstance(value, str) else json.dumps(value)
    path = f"/set/{key}"
    if ex_seconds:
        path += f"?EX={ex_seconds}"
    response = await client.post(path, content=payload.encode("utf-8"))
    response.raise_for_status()


async def cache_get(key: str) -> Any | None:
    client = get_client()
    response = await client.get(f"/get/{key}")
    response.raise_for_status()
    result = response.json().get("result")
    if result is None:
        return None
    try:
        return json.loads(result)
    except (json.JSONDecodeError, TypeError):
        return result


async def cache_delete(key: str) -> None:
    client = get_client()
    response = await client.post(f"/del/{key}")
    response.raise_for_status()


async def cache_incr(key: str) -> int:
    client = get_client()
    response = await client.post(f"/incr/{key}")
    response.raise_for_status()
    return int(response.json().get("result", 0))
