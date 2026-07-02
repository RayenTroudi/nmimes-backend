"""Supabase JWT verification and student-ownership checks."""

import time
from uuid import UUID

import httpx
import jwt
from fastapi import Header, HTTPException

from config import get_settings
from services import supabase_client

_jwks_cache: dict | None = None
_jwks_cache_fetched_at: float = 0.0
_JWKS_TTL_SECONDS = 3600


async def _fetch_jwks() -> dict:
    settings = get_settings()
    async with httpx.AsyncClient(timeout=httpx.Timeout(10.0)) as client:
        response = await client.get(f"{settings.supabase_url}/auth/v1/.well-known/jwks.json")
        response.raise_for_status()
        return response.json()


async def _get_jwks(force_refresh: bool = False) -> dict:
    global _jwks_cache, _jwks_cache_fetched_at
    now = time.monotonic()
    is_stale = _jwks_cache is None or (now - _jwks_cache_fetched_at) > _JWKS_TTL_SECONDS
    if force_refresh or is_stale:
        _jwks_cache = await _fetch_jwks()
        _jwks_cache_fetched_at = now
    return _jwks_cache


def _find_signing_key(jwks: dict, kid: str) -> dict | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


async def _verify_token(token: str) -> dict:
    try:
        unverified_header = jwt.get_unverified_header(token)
    except jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail="Malformed token") from exc

    kid = unverified_header.get("kid")
    jwks = await _get_jwks()
    signing_key_data = _find_signing_key(jwks, kid) if kid else None

    if signing_key_data is None:
        jwks = await _get_jwks(force_refresh=True)
        signing_key_data = _find_signing_key(jwks, kid) if kid else None
        if signing_key_data is None:
            raise HTTPException(status_code=401, detail="Unknown signing key")

    try:
        public_key = jwt.PyJWK.from_dict(signing_key_data).key
        payload = jwt.decode(
            token,
            key=public_key,
            algorithms=["ES256"],
            options={"verify_aud": False},
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(status_code=401, detail="Token expired") from exc
    except jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail="Invalid token") from exc

    return payload


async def get_current_parent(authorization: str = Header(...)) -> UUID:
    """FastAPI dependency: verifies the Supabase JWT and returns the parent's UUID (auth.uid())."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")
    token = authorization.removeprefix("Bearer ").strip()

    payload = await _verify_token(token)

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(status_code=401, detail="Token missing subject claim")

    try:
        return UUID(sub)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Token subject claim is not a valid UUID") from exc


async def get_current_parent_claims(authorization: str = Header(...)) -> dict:
    """Like get_current_parent, but returns the full verified JWT payload (needed for email)."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")
    token = authorization.removeprefix("Bearer ").strip()
    return await _verify_token(token)


async def verify_student_ownership(parent_id: UUID, student_id: UUID) -> None:
    """Raises 403 if student_id does not belong to parent_id."""
    student = await supabase_client.select_one(
        "students",
        filters={"id": f"eq.{student_id}", "parent_id": f"eq.{parent_id}"},
    )
    if student is None:
        raise HTTPException(status_code=403, detail="Student does not belong to this parent")
