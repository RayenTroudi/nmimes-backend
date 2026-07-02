import logging
from uuid import UUID

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from models.session import SessionResponse, StartSessionRequest, StepAnswerRequest
from services import supabase_client
from services.claude import detect_topic, evaluate_answer, format_sse, generate_first_question

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/sessions", tags=["sessions"])

SESSIONS_TABLE = "homework_sessions"
STEPS_TABLE = "session_steps"


@router.post("/start")
async def start_session(payload: StartSessionRequest) -> StreamingResponse:
    async def event_stream():
        try:
            topic_info = await detect_topic(payload.ocr_text)
            subject = topic_info["subject"]
            topic = topic_info["topic"]

            session_row = await supabase_client.insert_row(
                SESSIONS_TABLE,
                {
                    "student_id": str(payload.student_id),
                    "ocr_text": payload.ocr_text,
                    "image_url": payload.image_url,
                    "subject": subject,
                    "topic": topic,
                    "status": "active",
                },
            )
            session_id = session_row["id"]

            yield format_sse(
                "session_created",
                {"session_id": session_id, "subject": subject, "topic": topic},
            )

            question = await generate_first_question(payload.ocr_text, subject, topic)

            step_row = await supabase_client.insert_row(
                STEPS_TABLE,
                {
                    "session_id": session_id,
                    "step_number": 1,
                    "question": question,
                },
            )

            yield format_sse(
                "question",
                {
                    "step_id": step_row["id"],
                    "question": question,
                    "step_number": 1,
                    "is_final": False,
                },
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to start session")
            yield format_sse("error", {"message": str(exc)})

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@router.post("/{session_id}/step")
async def submit_step(session_id: UUID, payload: StepAnswerRequest) -> StreamingResponse:
    async def event_stream():
        try:
            session = await supabase_client.select_one(
                SESSIONS_TABLE, filters={"id": f"eq.{session_id}"}
            )
            if session is None:
                yield format_sse("error", {"message": "Session not found"})
                return

            step = await supabase_client.select_one(
                STEPS_TABLE, filters={"id": f"eq.{payload.step_id}"}
            )
            if step is None:
                yield format_sse("error", {"message": "Step not found"})
                return

            await supabase_client.update_rows(
                STEPS_TABLE,
                filters={"id": f"eq.{payload.step_id}"},
                data={"student_answer": payload.student_answer},
            )

            history_rows = await supabase_client.select_rows(
                STEPS_TABLE,
                filters={"session_id": f"eq.{session_id}"},
                order="step_number.asc",
            )
            history = [
                {"question": r["question"], "answer": r.get("student_answer", "")}
                for r in history_rows
                if r.get("student_answer")
            ]

            evaluation = await evaluate_answer(
                ocr_text=session["ocr_text"],
                question=step["question"],
                student_answer=payload.student_answer,
                history=history,
            )

            await supabase_client.update_rows(
                STEPS_TABLE,
                filters={"id": f"eq.{payload.step_id}"},
                data={"tier": evaluation["tier"], "feedback": evaluation["feedback"]},
            )

            yield format_sse(
                "evaluation",
                {
                    "tier": evaluation["tier"],
                    "feedback": evaluation["feedback"],
                },
            )

            if evaluation.get("is_complete"):
                await supabase_client.update_rows(
                    SESSIONS_TABLE,
                    filters={"id": f"eq.{session_id}"},
                    data={"status": "completed"},
                )
                yield format_sse("complete", {"session_id": str(session_id)})
                return

            next_step_number = step["step_number"] + 1
            next_question = evaluation.get("next_question")
            next_step_row = await supabase_client.insert_row(
                STEPS_TABLE,
                {
                    "session_id": str(session_id),
                    "step_number": next_step_number,
                    "question": next_question,
                },
            )

            yield format_sse(
                "question",
                {
                    "step_id": next_step_row["id"],
                    "question": next_question,
                    "step_number": next_step_number,
                    "is_final": False,
                },
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to process step")
            yield format_sse("error", {"message": str(exc)})

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: UUID) -> SessionResponse:
    session = await supabase_client.select_one(
        SESSIONS_TABLE, filters={"id": f"eq.{session_id}"}
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return SessionResponse(**session)
