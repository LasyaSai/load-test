"""
example_backend.py - Simple WebSocket backend for audio transcription.

Reference implementation for the developer-first workflow (NO STT required):
- Default behavior: return transcripts from a fixtures/transcripts.json mapping
  (recommended for initial testing with pre-defined audio files; requires NO API KEYS).
- Optional: replace the placeholder with a real STT provider later (OpenAI, Whisper, Groq).

Run with:
    python example_backend.py

Then set:
    export WEBSOCKET_URL=ws://localhost:8000/transcribe
"""

import asyncio
import base64
import json
import logging
from pathlib import Path

try:
    import websockets
    from websockets.server import WebSocketServerProtocol
except ImportError:
    raise RuntimeError(
        "websockets not installed. Install with: pip install websockets"
    )

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def handle_client(websocket: WebSocketServerProtocol):
    """Handle incoming WebSocket connections from the harness."""
    logger.info(f"Client connected: {websocket.remote_address}")
    
    try:
        # Receive audio data from harness
        message = await websocket.recv()
        payload = json.loads(message)
        
        # Extract audio bytes
        audio_b64 = payload.get("audio", "")
        filename = payload.get("filename", "audio.wav")
        
        if not audio_b64:
            await websocket.send(json.dumps({"error": "No audio data provided"}))
            return
        
        # Decode base64 to bytes
        try:
            audio_bytes = base64.b64decode(audio_b64)
        except Exception as e:
            await websocket.send(json.dumps({"error": f"Invalid base64 audio: {e}"}))
            return
        
        logger.info(f"Received audio: {filename} ({len(audio_bytes)} bytes)")
        
        # TODO: Transcribe audio_bytes using your chosen STT provider (local or cloud).
        # For the assignment, use the default fixture-driven mode (no API keys required):
        # the backend will return mapped transcripts from fixtures/transcripts.json.
        
        # Developer/default mode: use fixtures mapping or filename-stub
        transcript = transcribe_audio_placeholder(audio_bytes, filename)
        
        logger.info(f"Transcript: {transcript}")
        
        # Send response back to harness
        await websocket.send(json.dumps({"transcript": transcript}))
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        await websocket.send(json.dumps({"error": f"Invalid JSON: {e}"}))
    except Exception as e:
        logger.error(f"Error processing audio: {e}")
        await websocket.send(json.dumps({"error": f"Processing failed: {e}"}))


def transcribe_audio_placeholder(audio_bytes: bytes, filename: str = "audio.wav") -> str:
    """
    Placeholder transcription function that supports a no‑STT, fixture-driven mode.

    Behavior:
    - If a `fixtures/transcripts.json` file exists next to this script, it will be loaded
      and used to map incoming `filename` -> transcript. This is the recommended
      developer mode when you do NOT have any STT API keys.
    - Otherwise, falls back to returning the filename stem (underscores → spaces).

    This avoids requiring any external API keys for initial setup with pre-defined
    audio fixtures. STT/cloud provider examples are documented below as "optional"
    future work.
    """
    # Look for transcripts mapping in common fixtures locations
    possible_paths = [
        Path(__file__).parent / "fixtures" / "transcripts.json",
        Path(__file__).parent / ".." / "fixtures" / "transcripts.json",
        Path("fixtures") / "transcripts.json",
    ]

    for p in possible_paths:
        try:
            p = p.resolve()
        except Exception:
            pass
        if p.exists():
            try:
                with open(p, "r", encoding="utf-8") as f:
                    mapping = json.load(f)
                # mapping keys expected to be filenames (e.g., "weather_question.wav")
                key = filename if filename in mapping else Path(filename).name
                if key in mapping:
                    return mapping[key]
            except Exception:
                # ignore and fall back
                break

    # Default stub: return filename stem as readable text
    return Path(filename).stem.replace("_", " ")

# Optional STT provider notes (future work):
# - Optional: implement your chosen STT provider here (local or cloud)
# These are optional and should only be used when you have the required API keys
# and are ready to move beyond the pre-defined-fixtures developer workflow.


async def main():
    """Start the WebSocket server."""
    logger.info("Starting WebSocket server on ws://localhost:8000/transcribe")
    
    async with websockets.serve(handle_client, "localhost", 8000):
        logger.info("Server running. Waiting for connections...")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
