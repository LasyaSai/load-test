"""
websocket_client.py - Sends captured audio bytes to backend via WebSocket.

The backend is responsible for:
- Receiving audio bytes (WAV format)
- Running transcription (using any STT provider)
- Returning the transcript text

This removes the dependency on local transcription models or cloud APIs
and delegates all audio processing to the backend.
"""

import asyncio
import base64
import json
import os
from pathlib import Path
from typing import Optional


async def transcribe_via_websocket(audio_path: str) -> Optional[str]:
    """
    Send audio file to backend via WebSocket and get transcript.
    
    Args:
        audio_path: Path to WAV audio file
        
    Returns:
        Transcript string from backend, or None on error
        
    Raises:
        RuntimeError: If WEBSOCKET_URL is not set or connection fails
    """
    websocket_url = os.environ.get("WEBSOCKET_URL")
    if not websocket_url:
        raise RuntimeError(
            "WEBSOCKET_URL env var not set. "
            "Expected format: ws://localhost:8000/transcribe or wss://api.example.com/transcribe"
        )
    
    if not Path(audio_path).exists():
        raise RuntimeError(f"Audio file not found: {audio_path}")
    
    # Read audio bytes
    with open(audio_path, "rb") as f:
        audio_bytes = f.read()
    
    # Encode as base64 for JSON transmission
    audio_b64 = base64.b64encode(audio_bytes).decode("ascii")
    
    try:
        import websockets
    except ImportError:
        raise RuntimeError(
            "websockets library not installed. "
            "Install with: pip install websockets"
        )
    
    payload = {
        "audio": audio_b64,
        "format": "wav",
        "filename": Path(audio_path).name,
    }
    
    try:
        async with websockets.connect(websocket_url, ping_interval=None) as websocket:
            # Send audio data
            await websocket.send(json.dumps(payload))
            
            # Receive transcript
            response_text = await asyncio.wait_for(websocket.recv(), timeout=60.0)
            response = json.loads(response_text)
            
            if "error" in response:
                raise RuntimeError(f"Backend error: {response['error']}")
            
            transcript = response.get("transcript", "").strip()
            if not transcript:
                raise RuntimeError("Backend returned empty transcript")
            
            return transcript
    except asyncio.TimeoutError:
        raise RuntimeError("WebSocket transcription timed out after 60 seconds")
    except Exception as e:
        raise RuntimeError(f"WebSocket transcription failed: {e}")


def transcribe(audio_path: str) -> str:
    """
    Synchronous wrapper around async WebSocket transcription.
    
    Args:
        audio_path: Path to WAV audio file
        
    Returns:
        Transcript string
        
    Raises:
        RuntimeError: If transcription fails or WEBSOCKET_URL not set
    """
    websocket_url = os.environ.get("WEBSOCKET_URL")
    
    if not websocket_url:
        # Stub for dry-run testing: return filename without extension
        return Path(audio_path).stem.replace("_", " ")
    
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        return loop.run_until_complete(transcribe_via_websocket(audio_path))
    finally:
        loop.close()
