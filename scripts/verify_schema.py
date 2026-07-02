"""One-off script to verify the Supabase schema migration applied correctly.

Run manually after applying migrations: python scripts/verify_schema.py <auth-users-uuid>
Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in nmimes-api/.env.
Uses the service-role key, so this only validates schema shape/constraints/cascades,
not RLS policies (RLS requires a real authenticated session to exercise).
"""

import asyncio
import os
import sys
from pathlib import Path

import httpx
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "nmimes-api" / ".env")

SUPABASE_URL = os.environ["SUPABASE_URL"]
SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

HEADERS = {
    "apikey": SERVICE_ROLE_KEY,
    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}


async def main() -> None:
    async with httpx.AsyncClient(base_url=f"{SUPABASE_URL}/rest/v1", headers=HEADERS) as client:
        if len(sys.argv) < 2:
            print("Usage: python verify_schema.py <existing-auth-users-uuid>")
            sys.exit(1)
        auth_user_id = sys.argv[1]

        print("1. Inserting parent...")
        resp = await client.post(
            "/parents",
            json={
                "id": auth_user_id,
                "first_name": "Test",
                "last_name": "Parent",
                "email": "test-parent@example.com",
            },
        )
        resp.raise_for_status()
        parent = resp.json()[0]
        assert parent["subscription_status"] == "free", "default subscription_status should be 'free'"
        print(f"   OK parent id={parent['id']}")

        print("2. Inserting student...")
        resp = await client.post(
            "/students",
            json={
                "parent_id": parent["id"],
                "name": "Test Student",
                "access_code_hash": "dummy-bcrypt-hash",
            },
        )
        resp.raise_for_status()
        student = resp.json()[0]
        assert student["points_balance"] == 0, "default points_balance should be 0"
        print(f"   OK student id={student['id']}")

        print("3. Inserting homework_session...")
        resp = await client.post(
            "/homework_sessions",
            json={"student_id": student["id"], "ocr_text": "2x + 5 = 15"},
        )
        resp.raise_for_status()
        session = resp.json()[0]
        assert session["status"] == "active", "default status should be 'active'"
        print(f"   OK session id={session['id']}")

        print("4. Inserting session_step...")
        resp = await client.post(
            "/session_steps",
            json={"session_id": session["id"], "step_number": 1, "question": "What operation isolates x?"},
        )
        resp.raise_for_status()
        step = resp.json()[0]
        print(f"   OK step id={step['id']}")

        print("5. Rejecting invalid tier value...")
        resp = await client.post(
            "/session_steps",
            json={
                "session_id": session["id"],
                "step_number": 2,
                "question": "test",
                "tier": "not-a-real-tier",
            },
        )
        assert resp.status_code >= 400, "invalid tier should be rejected by CHECK constraint"
        print(f"   OK rejected with status {resp.status_code}")

        print("6. Inserting teach_it_back_attempt...")
        resp = await client.post(
            "/teach_it_back_attempts",
            json={"session_id": session["id"], "transcript": "x equals five", "clarity_score": 80},
        )
        resp.raise_for_status()
        attempt = resp.json()[0]
        print(f"   OK attempt id={attempt['id']}")

        print("7. Deleting parent (should cascade)...")
        resp = await client.delete(f"/parents?id=eq.{parent['id']}")
        resp.raise_for_status()

        resp = await client.get(f"/students?id=eq.{student['id']}")
        resp.raise_for_status()
        assert resp.json() == [], "student should have been cascade-deleted with parent"
        print("   OK cascade delete verified")

        print("\nAll schema checks passed.")


if __name__ == "__main__":
    asyncio.run(main())
