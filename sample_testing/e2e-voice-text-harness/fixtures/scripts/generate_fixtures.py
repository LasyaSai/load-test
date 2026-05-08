#!/usr/bin/env python3
"""
generate_fixtures.py — Generates synthetic WAV fixtures using TTS (gTTS or pyttsx3).
Run this once to create the audio files needed for voice test cases.

Usage:
    pip install gTTS
    python fixtures/scripts/generate_fixtures.py

Output: WAV files written to fixtures/
"""

import os
import subprocess
from pathlib import Path

FIXTURES_DIR = Path(__file__).resolve().parents[1]

FIXTURES = {
    "hello_how_are_you.wav": "Hello! How are you doing today?",
    "weather.wav": "What's the weather like in Dubai today?",
    "movie.wav": "Can you help me book a movie ticket?",
    "news.wav": "What is latest news regarding AI.",
    "travel.wav": "Where is good place to travel in UAE during May",
}


def generate_with_gtts():
    """Generate fixtures using Google TTS (requires internet)."""
    try:
        from gtts import gTTS
        import io
        # gTTS produces MP3; convert to WAV via ffmpeg
        for filename, text in FIXTURES.items():
            out_path = FIXTURES_DIR / filename
            if out_path.exists():
                print(f"  skip (exists): {filename}")
                continue
            print(f"  generating: {filename}")
            tts = gTTS(text=text, lang="en", slow=False)
            mp3_path = out_path.with_suffix(".mp3")
            tts.save(str(mp3_path))
            # Convert MP3 → WAV (16kHz mono, 16-bit PCM)
            subprocess.run([
                "ffmpeg", "-y", "-i", str(mp3_path),
                "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le",
                str(out_path)
            ], check=True, capture_output=True)
            mp3_path.unlink()
        print("\nDone. Fixtures written to:", FIXTURES_DIR)
    except ImportError:
        print("gTTS not installed. Run: pip install gTTS")
        generate_with_say_command()


def generate_with_say_command():
    """macOS fallback: use `say` command (no internet required)."""
    print("Falling back to macOS `say` command...")
    for filename, text in FIXTURES.items():
        out_path = FIXTURES_DIR / filename
        if out_path.exists():
            print(f"  skip (exists): {filename}")
            continue
        print(f"  generating: {filename}")
        aiff_path = out_path.with_suffix(".aiff")
        subprocess.run(["say", "-o", str(aiff_path), text], check=True)
        subprocess.run([
            "afconvert", str(aiff_path), str(out_path),
            "-d", "LEI16", "-f", "WAVE", "--rate", "16000"
        ], check=True)
        aiff_path.unlink()
    print("\nDone. Fixtures written to:", FIXTURES_DIR)


if __name__ == "__main__":
    FIXTURES_DIR.mkdir(exist_ok=True)
    if subprocess.run(["which", "ffmpeg"], capture_output=True).returncode == 0:
        generate_with_gtts()
    else:
        generate_with_say_command()
