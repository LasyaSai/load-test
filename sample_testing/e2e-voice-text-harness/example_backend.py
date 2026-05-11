"""
example_backend.py - Simple WebSocket backend for audio transcription.

This is a reference implementation showing how to accept audio bytes over WebSocket
and return transcriptions. You can use any STT provider (local Whisper, OpenAI, Groq, etc.).

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


async def handle_client(websocket: WebSocketServerProtocol, path: str):
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
        
        # TODO: Transcribe audio_bytes using your preferred STT provider
        # Options:
        #   1. Local: whisper (pip install openai-whisper)
        #   2. OpenAI API: whisper-1 model
        #   3. Groq API: whisper-large-v3
        #   4. Google Cloud Speech-to-Text
        #   5. Azure Speech Services
        #   etc.
        
        # PLACEHOLDER: Return dummy transcript for testing
        # In production, replace this with actual transcription
        transcript = transcribe_audio_placeholder(audio_bytes)
        
        logger.info(f"Transcript: {transcript}")
        
        # Send response back to harness
        await websocket.send(json.dumps({"transcript": transcript}))
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        await websocket.send(json.dumps({"error": f"Invalid JSON: {e}"}))
    except Exception as e:
        logger.error(f"Error processing audio: {e}")
        await websocket.send(json.dumps({"error": f"Processing failed: {e}"}))


def transcribe_audio_placeholder(audio_bytes: bytes) -> str:
    """
    Placeholder transcription function.
    
    In production, replace this with actual STT logic.
    
    Example implementations:
    
    # Option 1: Use local Whisper
    import whisper
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(audio_bytes)
        model = whisper.load_model("base")
        result = model.transcribe(f.name)
        return result["text"]
    
    # Option 2: Use OpenAI API
    import openai
    transcript = openai.Audio.transcribe("whisper-1", audio_bytes)
    return transcript["text"]
    
    # Option 3: Use Groq API
    import groq
    client = groq.Groq(api_key="...")
    result = client.audio.transcriptions.create(
        file=("audio.wav", audio_bytes, "audio/wav"),
        model="whisper-large-v3"
    )
    return result.text
    """
    # STUB: Return filename-based dummy text for development
    return "the assistant responded with the correct information"


async def main():
    """Start the WebSocket server."""
    logger.info("Starting WebSocket server on ws://localhost:8000/transcribe")
    
    async with websockets.serve(handle_client, "localhost", 8000):
        logger.info("Server running. Waiting for connections...")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
