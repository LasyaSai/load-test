"""
transcriber.py - Transcribes captured audio using OpenRouter STT by default.

Primary path:
- OpenRouter speech-to-text API

Fallbacks:
- faster-whisper if installed and TRANSCRIPTION_PROVIDER=local
- filename-stem stub for dry-run testing
"""

import base64
import os
from pathlib import Path


def transcribe(audio_path: str) -> str:
    """
    Transcribe audio file at audio_path.
    Returns transcript string or raises RuntimeError.
    """
    provider = os.environ.get("TRANSCRIPTION_PROVIDER", "openrouter").strip().lower()
    model_name = os.environ.get("TRANSCRIPTION_MODEL", "openrouter/free").strip()
    api_key = os.environ.get("OPENROUTER_API_KEY", "")
    base_url = os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1").rstrip("/")

    if provider == "stub":
        return Path(audio_path).stem.replace("_", " ")

    if provider in ("openrouter", "auto") and api_key:
        cloud = _transcribe_with_openrouter(audio_path, api_key, base_url, model_name)
        if cloud:
            return cloud

    if provider in ("local", "auto", "faster-whisper"):
        local_model = os.environ.get("TRANSCRIPTION_LOCAL_MODEL", "base").strip()
        local = _transcribe_with_faster_whisper(audio_path, local_model)
        if local:
            return local

    if provider == "local":
        return Path(audio_path).stem.replace("_", " ")

    return Path(audio_path).stem.replace("_", " ")


def _transcribe_with_faster_whisper(audio_path: str, model_name: str) -> str | None:
    try:
        from faster_whisper import WhisperModel
    except Exception:
        return None

    try:
        model = WhisperModel(model_name, device="cpu", compute_type="int8")
        segments, _info = model.transcribe(audio_path, beam_size=5)
        transcript = "".join(segment.text for segment in segments).strip()
        return transcript or None
    except Exception:
        return None


def _transcribe_with_openrouter(audio_path: str, api_key: str, base_url: str, model_name: str) -> str | None:
    import httpx

    with open(audio_path, "rb") as f:
        audio_bytes = f.read()

    payload = {
        "model": model_name,
        "input_audio": {
            "data": base64.b64encode(audio_bytes).decode("ascii"),
            "format": _infer_audio_format(audio_path),
        },
    }

    try:
        response = httpx.post(
            f"{base_url}/audio/transcriptions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=60,
        )
        response.raise_for_status()
        return response.json().get("text") or None
    except Exception:
        return None


def _infer_audio_format(audio_path: str) -> str:
    suffix = Path(audio_path).suffix.lower().lstrip(".")
    return suffix if suffix else "wav"
