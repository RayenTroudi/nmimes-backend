import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from models.student import CreateStudentRequest, StudentResponse, VerifyAccessCodeRequest
from services import supabase_client
from services.access_code import hash_access_code, verify_access_code
from services.auth import get_current_parent, verify_student_ownership
from services.redis_client import cache_get, cache_set, increment_with_expiry
from services.supabase_client import select_one

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/students", tags=["students"])

STUDENTS_TABLE = "students"
RATE_LIMIT_MAX_ATTEMPTS = 10
RATE_LIMIT_WINDOW_SECONDS = 900
PROFILE_CACHE_TTL_SECONDS = 60
PROFILE_CACHE_KEY_PREFIX = "student_profile:"


@router.post("", response_model=StudentResponse)
async def create_student(
    payload: CreateStudentRequest, parent_id: UUID = Depends(get_current_parent)
) -> StudentResponse:
    student_row = await supabase_client.insert_row(
        STUDENTS_TABLE,
        {
            "parent_id": str(parent_id),
            "name": payload.name,
            "username": payload.username,
            "grade": payload.grade,
            "interest": payload.interest,
            "access_code_hash": hash_access_code(payload.access_code),
        },
    )
    return StudentResponse(**student_row)


@router.post("/verify-access-code", response_model=StudentResponse)
async def verify_student_access_code(
    payload: VerifyAccessCodeRequest, parent_id: UUID = Depends(get_current_parent)
) -> StudentResponse:
    attempts = await increment_with_expiry(
        f"access_code_attempts:{parent_id}", RATE_LIMIT_WINDOW_SECONDS
    )
    if attempts > RATE_LIMIT_MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many access code attempts, try again later")

    students = await supabase_client.select_rows(
        STUDENTS_TABLE, filters={"parent_id": f"eq.{parent_id}"}
    )
    for student in students:
        if verify_access_code(payload.access_code, student["access_code_hash"]):
            return StudentResponse(**student)

    raise HTTPException(status_code=404, detail="No matching student for this access code")


@router.get("/{student_id}/profile")
async def get_student_profile(
    student_id: UUID, parent_id: UUID = Depends(get_current_parent)
) -> dict:
    # Ownership is checked before any cache read so a non-owner can never
    # read another student's cached profile.
    await verify_student_ownership(parent_id, student_id)

    cache_key = f"{PROFILE_CACHE_KEY_PREFIX}{student_id}"
    cached = await cache_get(cache_key)
    if cached is not None:
        return {"cached": True, "profile": cached}

    row = await select_one(STUDENTS_TABLE, filters={"id": f"eq.{student_id}"})
    if row is None:
        raise HTTPException(status_code=404, detail="Student not found")

    profile = {
        "id": row["id"],
        "name": row["name"],
        "points_balance": row["points_balance"],
        "avatar_url": row.get("avatar_url"),
    }
    await cache_set(cache_key, profile, ex_seconds=PROFILE_CACHE_TTL_SECONDS)
    return {"cached": False, "profile": profile}
