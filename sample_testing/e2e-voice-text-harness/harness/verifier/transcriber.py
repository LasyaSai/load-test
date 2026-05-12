"""
Compatibility shim for transcriber interface.

This file provides a backwards-compatible `transcribe(audio_path)` function
that forwards to the WebSocket-based transcription client used by the
verifier. Keeping this shim avoids import errors if any remaining code
still imports `transcriber`.

Prefer using `harness.verifier.websocket_client.transcribe` directly.
"""

# Attempt relative import first, fall back to absolute import for flexibility
try:
    from .websocket_client import transcribe as _ws_transcribe  # type: ignore
except Exception:
    try:
        from harness.verifier.websocket_client import transcribe as _ws_transcribe  # type: ignore
    except Exception:
        _ws_transcribe = None


def transcribe(audio_path: str) -> str:
    """Forward to the WebSocket client if available.

    If the WebSocket client is not importable, raise a helpful error that
    points the developer to BACKEND_SETUP.md for running the developer
    backend or setting WEBSOCKET_URL.
    """
    if _ws_transcribe is None:
        raise RuntimeError(
            "Transcription backend not available.\n"
            "Set WEBSOCKET_URL and ensure the developer backend is running, or see BACKEND_SETUP.md for developer instructions."
        )
    return _ws_transcribe(audio_path)
