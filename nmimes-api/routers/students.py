import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from models.student import CreateStudentRequest, StudentResponse, VerifyAccessCodeRequest
from services import supabase_client
from services.access_code import hash_access_code, verify_access_code
from services.auth import get_current_parent
from services.redis_client import increment_with_expiry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/students", tags=["students"])

STUDENTS_TABLE = "students"
RATE_LIMIT_MAX_ATTEMPTS = 10
RATE_LIMIT_WINDOW_SECONDS = 900


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
