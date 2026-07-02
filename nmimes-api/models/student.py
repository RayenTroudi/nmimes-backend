from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CreateStudentRequest(BaseModel):
    name: str = Field(..., min_length=1)
    username: str | None = None
    grade: str | None = None
    interest: str | None = None
    access_code: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


class StudentResponse(BaseModel):
    id: UUID
    parent_id: UUID
    name: str
    username: str | None = None
    grade: str | None = None
    interest: str | None = None
    points_balance: int
    avatar_url: str | None = None
    created_at: datetime
    updated_at: datetime


class VerifyAccessCodeRequest(BaseModel):
    access_code: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")
