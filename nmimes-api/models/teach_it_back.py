from uuid import UUID

from pydantic import BaseModel, Field


class TeachItBackRequest(BaseModel):
    """Either text or audio_base64 must be provided (validated in the route)."""

    text: str | None = None
    audio_base64: str | None = None
    audio_format: str = Field(default="webm", description="Audio container format, e.g. webm, mp3, wav")


class TeachItBackResponse(BaseModel):
    session_id: UUID
    transcript: str
    clarity_score: int = Field(..., ge=0, le=100)
    feedback: str
    strengths: list[str]
    gaps: list[str]
