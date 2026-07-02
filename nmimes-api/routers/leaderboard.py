import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter

from services import supabase_client
from services.redis_client import cache_get, cache_set

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])

SESSIONS_TABLE = "homework_sessions"
CACHE_KEY = "leaderboard:weekly"
CACHE_TTL_SECONDS = 300


@router.get("/weekly")
async def weekly_leaderboard() -> dict:
    cached = await cache_get(CACHE_KEY)
    if cached is not None:
        return {"cached": True, "entries": cached}

    week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()

    sessions = await supabase_client.select_rows(
        SESSIONS_TABLE,
        filters={
            "status": "eq.completed",
            "created_at": f"gte.{week_ago}",
            "select": "student_id",
        },
    )

    counts: dict[str, int] = {}
    for row in sessions:
        student_id = row["student_id"]
        counts[student_id] = counts.get(student_id, 0) + 1

    entries = sorted(
        ({"student_id": sid, "completed_sessions": count} for sid, count in counts.items()),
        key=lambda e: e["completed_sessions"],
        reverse=True,
    )[:50]

    await cache_set(CACHE_KEY, entries, ex_seconds=CACHE_TTL_SECONDS)

    return {"cached": False, "entries": entries}
