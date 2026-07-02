import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from models.teach_it_back import TeachItBackRequest, TeachItBackResponse
from services import supabase_client
from services.claude import evaluate_teach_it_back
from services.whisper import transcribe_audio
from services.auth import get_current_parent, verify_student_ownership

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/teach-it-back", tags=["teach-it-back"])

SESSIONS_TABLE = "homework_sessions"
TEACH_IT_BACK_TABLE = "teach_it_back_attempts"


@router.post("/{session_id}", response_model=TeachItBackResponse)
async def teach_it_back(
    session_id: UUID, payload: TeachItBackRequest, parent_id: UUID = Depends(get_current_parent)
) -> TeachItBackResponse:
    if not payload.text and not payload.audio_base64:
        raise HTTPException(status_code=422, detail="Either 'text' or 'audio_base64' must be provided")

    session = await supabase_client.select_one(
        SESSIONS_TABLE, filters={"id": f"eq.{session_id}"}
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    await verify_student_ownership(parent_id, UUID(session["student_id"]))

    if payload.audio_base64:
        transcript = await transcribe_audio(payload.audio_base64, payload.audio_format)
    else:
        transcript = payload.text or ""

    evaluation = await evaluate_teach_it_back(topic=session.get("topic", "the concept"), transcript=transcript)

    await supabase_client.insert_row(
        TEACH_IT_BACK_TABLE,
        {
            "session_id": str(session_id),
            "transcript": transcript,
            "clarity_score": evaluation["clarity_score"],
            "feedback": evaluation["feedback"],
            "strengths": evaluation.get("strengths", []),
            "gaps": evaluation.get("gaps", []),
        },
    )

    return TeachItBackResponse(
        session_id=session_id,
        transcript=transcript,
        clarity_score=evaluation["clarity_score"],
        feedback=evaluation["feedback"],
        strengths=evaluation.get("strengths", []),
        gaps=evaluation.get("gaps", []),
    )
