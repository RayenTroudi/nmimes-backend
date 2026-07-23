"""Standalone verification for GET /students/{id}/profile using Starlette's
TestClient with all external services monkeypatched. Run with the repo venv:
    .venv/Scripts/python.exe verify_profile_endpoint.py
Exits non-zero on any failed assertion.
"""
import sys
from uuid import UUID

from fastapi.testclient import TestClient

import routers.students as students_router
import services.auth as auth
from main import app

STUDENT_ID = "11111111-1111-1111-1111-111111111111"
OWNER_ID = "22222222-2222-2222-2222-222222222222"
OTHER_ID = "33333333-3333-3333-3333-333333333333"

STUDENT_ROW = {
    "id": STUDENT_ID,
    "parent_id": OWNER_ID,
    "name": "Amina",
    "points_balance": 240,
    "avatar_url": None,
    "created_at": "2026-07-23T00:00:00+00:00",
    "updated_at": "2026-07-23T00:00:00+00:00",
}


def run():
    # Fake auth: pretend the caller is OWNER_ID.
    app.dependency_overrides[auth.get_current_parent] = lambda: UUID(OWNER_ID)

    # Fake ownership: owner passes, anyone else 403.
    async def fake_ownership(parent_id, student_id):
        from fastapi import HTTPException
        if str(parent_id) != OWNER_ID or str(student_id) != STUDENT_ID:
            raise HTTPException(status_code=403, detail="not owner")
    students_router.verify_student_ownership = fake_ownership

    # In-memory fake Redis.
    store = {}

    async def fake_cache_get(key):
        return store.get(key)

    async def fake_cache_set(key, value, ex_seconds=None):
        store[key] = value

    students_router.cache_get = fake_cache_get
    students_router.cache_set = fake_cache_set

    # Fake Supabase select_one.
    calls = {"select_one": 0}

    async def fake_select_one(table, filters, select="*"):
        calls["select_one"] += 1
        if table == "students" and filters.get("id") == f"eq.{STUDENT_ID}":
            return STUDENT_ROW
        return None

    students_router.select_one = fake_select_one

    client = TestClient(app)

    # 1. First call -> cache miss, hits Supabase.
    r1 = client.get(f"/students/{STUDENT_ID}/profile")
    assert r1.status_code == 200, r1.text
    body1 = r1.json()
    assert body1["cached"] is False, body1
    assert body1["profile"]["name"] == "Amina", body1
    assert body1["profile"]["points_balance"] == 240, body1
    assert body1["profile"]["avatar_url"] is None, body1
    assert body1["profile"]["id"] == STUDENT_ID, body1
    assert calls["select_one"] == 1, calls

    # 2. Second call -> cache hit, does NOT hit Supabase again.
    r2 = client.get(f"/students/{STUDENT_ID}/profile")
    assert r2.status_code == 200, r2.text
    body2 = r2.json()
    assert body2["cached"] is True, body2
    assert body2["profile"]["name"] == "Amina", body2
    assert calls["select_one"] == 1, calls  # unchanged

    # 3. Non-owner -> 403.
    app.dependency_overrides[auth.get_current_parent] = lambda: UUID(OTHER_ID)
    r3 = client.get(f"/students/{STUDENT_ID}/profile")
    assert r3.status_code == 403, r3.text

    # 4. Unknown student -> 404 (owner of a non-existent id).
    app.dependency_overrides[auth.get_current_parent] = lambda: UUID(OWNER_ID)
    unknown = "44444444-4444-4444-4444-444444444444"

    async def owns_anything(parent_id, student_id):
        return None
    students_router.verify_student_ownership = owns_anything
    r4 = client.get(f"/students/{unknown}/profile")
    assert r4.status_code == 404, r4.text

    print("OK: profile endpoint verification passed")


if __name__ == "__main__":
    try:
        run()
    except AssertionError as exc:
        print(f"FAILED: {exc}")
        sys.exit(1)
