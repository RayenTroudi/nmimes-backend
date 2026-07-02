"""OpenAI Whisper audio transcription via httpx async."""

import base64

import httpx

from config import get_settings

OPENAI_TRANSCRIPTION_URL = "https://api.openai.com/v1/audio/transcriptions"


async def transcribe_audio(audio_base64: str, audio_format: str = "webm") -> str:
    """Transcribe base64-encoded audio using OpenAI Whisper."""
    settings = get_settings()
    audio_bytes = base64.b64decode(audio_base64)

    files = {"file": (f"audio.{audio_format}", audio_bytes, f"audio/{audio_format}")}
    data = {"model": "whisper-1"}

    async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
        response = await client.post(
            OPENAI_TRANSCRIPTION_URL,
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            files=files,
            data=data,
        )
        response.raise_for_status()
        return response.json()["text"]
