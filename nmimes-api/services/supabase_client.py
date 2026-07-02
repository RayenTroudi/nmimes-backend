"""Async Supabase client backed by httpx, using the service-role key (bypasses RLS)."""

from typing import Any

import httpx

from config import get_settings

_client: httpx.AsyncClient | None = None


def _headers() -> dict[str, str]:
    settings = get_settings()
    return {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }


async def init_supabase_client() -> None:
    global _client
    settings = get_settings()
    _client = httpx.AsyncClient(
        base_url=f"{settings.supabase_url}/rest/v1",
        headers=_headers(),
        timeout=httpx.Timeout(30.0),
    )


async def close_supabase_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


def get_client() -> httpx.AsyncClient:
    if _client is None:
        raise RuntimeError("Supabase client not initialized. Call init_supabase_client() in app lifespan.")
    return _client


async def insert_row(table: str, data: dict[str, Any]) -> dict[str, Any]:
    """Insert a single row and return the created record."""
    client = get_client()
    response = await client.post(
        f"/{table}",
        json=data,
        headers={"Prefer": "return=representation"},
    )
    response.raise_for_status()
    rows = response.json()
    return rows[0] if rows else {}


async def upsert_row(table: str, data: dict[str, Any], on_conflict: str = "id") -> dict[str, Any]:
    """Insert a row, or update it in place if on_conflict's column value already exists."""
    client = get_client()
    response = await client.post(
        f"/{table}",
        json=data,
        params={"on_conflict": on_conflict},
        headers={"Prefer": "return=representation,resolution=merge-duplicates"},
    )
    response.raise_for_status()
    rows = response.json()
    return rows[0] if rows else {}


async def update_rows(table: str, filters: dict[str, str], data: dict[str, Any]) -> list[dict[str, Any]]:
    """Update rows matching PostgREST-style filters, e.g. {'id': 'eq.<uuid>'}."""
    client = get_client()
    response = await client.patch(
        f"/{table}",
        params=filters,
        json=data,
        headers={"Prefer": "return=representation"},
    )
    response.raise_for_status()
    return response.json()


async def select_rows(
    table: str,
    filters: dict[str, str] | None = None,
    select: str = "*",
    order: str | None = None,
    limit: int | None = None,
) -> list[dict[str, Any]]:
    client = get_client()
    params: dict[str, Any] = {"select": select, **(filters or {})}
    if order:
        params["order"] = order
    if limit:
        params["limit"] = str(limit)
    response = await client.get(f"/{table}", params=params)
    response.raise_for_status()
    return response.json()


async def select_one(table: str, filters: dict[str, str], select: str = "*") -> dict[str, Any] | None:
    rows = await select_rows(table, filters=filters, select=select, limit=1)
    return rows[0] if rows else None
