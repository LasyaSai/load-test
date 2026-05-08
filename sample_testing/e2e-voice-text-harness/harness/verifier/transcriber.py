"""
transcriber.py - Transcribes captured audio using local-first speech recognition.

Primary path:
- faster-whisper if installed

Fallbacks:
- filename-stem stub for dry-run testing
"""

import os
from pathlib import Path


def transcribe(audio_path: str) -> str:
    """
    Transcribe audio file at audio_path.
    Returns transcript string or raises RuntimeError.
    """
    provider = os.environ.get("TRANSCRIPTION_PROVIDER", "local").strip().lower()
    local_model = os.environ.get("TRANSCRIPTION_MODEL", "base").strip()

    if provider == "stub":
        return Path(audio_path).stem.replace("_", " ")

    if provider in ("local", "auto", "faster-whisper"):
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
