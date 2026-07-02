from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class StartSessionRequest(BaseModel):
    student_id: UUID
    ocr_text: str = Field(..., min_length=1, description="OCR-extracted text from homework image")
    image_url: str | None = None


class StepAnswerRequest(BaseModel):
    step_id: UUID
    student_answer: str = Field(..., min_length=1)


class SessionResponse(BaseModel):
    id: UUID
    student_id: UUID
    subject: str | None = None
    topic: str | None = None
    status: Literal["active", "completed", "abandoned"]
    created_at: datetime
    updated_at: datetime


class SocraticStep(BaseModel):
    step_id: UUID
    question: str
    step_number: int
    is_final: bool = False


class EvaluationTier(BaseModel):
    """4-tier Socratic evaluation result."""

    tier: Literal["correct", "partially_correct", "incorrect", "off_topic"]
    feedback: str
    next_question: str | None = None
    is_complete: bool = False
