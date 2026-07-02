"""Claude API integration: topic detection, Socratic questioning, and answer evaluation."""

import json
from collections.abc import AsyncGenerator
from typing import Any

import httpx

from config import get_settings

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"

TOPIC_DETECTION_SYSTEM = (
    "You are an expert curriculum analyst. Given OCR-extracted homework text, identify the "
    "subject and specific topic. Respond ONLY with compact JSON: "
    '{"subject": "<subject>", "topic": "<specific topic>"}'
)

SOCRATIC_SYSTEM = (
    "You are a patient Socratic tutor for K-12 students. You never give direct answers. "
    "Instead, you ask a single guiding question that helps the student discover the next step "
    "themselves, based on the homework content and the conversation so far. Keep questions short, "
    "encouraging, and age-appropriate. Respond with plain text containing only the question."
)

EVALUATION_SYSTEM = (
    "You are a Socratic tutor evaluating a student's answer to your guiding question. "
    "Classify the answer into exactly one of four tiers:\n"
    "- correct: the answer is accurate and demonstrates understanding\n"
    "- partially_correct: the answer is on the right track but incomplete or has minor errors\n"
    "- incorrect: the answer is wrong but shows an attempt\n"
    "- off_topic: the answer does not engage with the question\n\n"
    "Then decide the next step:\n"
    "- If correct and this concludes the problem, set is_complete=true and next_question=null\n"
    "- If correct but more steps remain, provide the next Socratic guiding question\n"
    "- If partially_correct, incorrect, or off_topic, provide a Socratic follow-up question that "
    "nudges the student toward the correct reasoning without revealing the answer\n\n"
    "Respond ONLY with compact JSON matching this schema: "
    '{"tier": "<tier>", "feedback": "<1-2 sentence encouraging feedback>", '
    '"next_question": "<question or null>", "is_complete": <true|false>}'
)


def _client() -> httpx.AsyncClient:
    settings = get_settings()
    return httpx.AsyncClient(
        base_url="https://api.anthropic.com",
        headers={
            "x-api-key": settings.anthropic_api_key,
            "anthropic-version": ANTHROPIC_VERSION,
            "content-type": "application/json",
        },
        timeout=httpx.Timeout(60.0),
    )


async def _call_claude(system: str, user_message: str, max_tokens: int = 1024) -> str:
    settings = get_settings()
    async with _client() as client:
        response = await client.post(
            "/v1/messages",
            json={
                "model": settings.claude_model,
                "max_tokens": max_tokens,
                "system": system,
                "messages": [{"role": "user", "content": user_message}],
            },
        )
        response.raise_for_status()
        data = response.json()
        return "".join(block["text"] for block in data["content"] if block["type"] == "text")


async def detect_topic(ocr_text: str) -> dict[str, str]:
    """Detect subject and topic from OCR'd homework text."""
    raw = await _call_claude(TOPIC_DETECTION_SYSTEM, ocr_text)
    try:
        parsed = json.loads(raw)
        return {"subject": parsed.get("subject", "Unknown"), "topic": parsed.get("topic", "Unknown")}
    except json.JSONDecodeError:
        return {"subject": "Unknown", "topic": "Unknown"}


async def generate_first_question(ocr_text: str, subject: str, topic: str) -> str:
    """Generate the opening Socratic question for a new session."""
    user_message = (
        f"Subject: {subject}\nTopic: {topic}\nHomework content:\n{ocr_text}\n\n"
        "Ask the first guiding Socratic question to start helping the student solve this."
    )
    return await _call_claude(SOCRATIC_SYSTEM, user_message)


async def evaluate_answer(
    ocr_text: str, question: str, student_answer: str, history: list[dict[str, str]] | None = None
) -> dict[str, Any]:
    """Run 4-tier Socratic evaluation of a student's answer."""
    history_text = ""
    if history:
        history_text = "\n\nPrior conversation:\n" + "\n".join(
            f"Q: {h['question']}\nA: {h['answer']}" for h in history
        )
    user_message = (
        f"Homework content:\n{ocr_text}\n\n"
        f"Guiding question asked: {question}\n"
        f"Student's answer: {student_answer}"
        f"{history_text}"
    )
    raw = await _call_claude(EVALUATION_SYSTEM, user_message)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {
            "tier": "incorrect",
            "feedback": "Let's try that again.",
            "next_question": "Can you walk me through your thinking so far?",
            "is_complete": False,
        }


async def evaluate_teach_it_back(topic: str, transcript: str) -> dict[str, Any]:
    """Evaluate a student's spoken/typed explanation of a concept they just learned."""
    system = (
        "You evaluate a student's attempt to teach back a concept they just learned, to check "
        "for genuine understanding (the Feynman technique). Respond ONLY with compact JSON: "
        '{"clarity_score": <0-100 int>, "feedback": "<2-3 sentence feedback>", '
        '"strengths": ["<strength>", ...], "gaps": ["<gap>", ...]}'
    )
    user_message = f"Topic: {topic}\n\nStudent's explanation:\n{transcript}"
    raw = await _call_claude(system, user_message)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"clarity_score": 50, "feedback": "Good attempt.", "strengths": [], "gaps": []}


async def stream_sse_event(event: str, data: dict[str, Any]) -> AsyncGenerator[str, None]:
    """Yield a single formatted SSE event."""
    yield f"event: {event}\ndata: {json.dumps(data)}\n\n"


def format_sse(event: str, data: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"
