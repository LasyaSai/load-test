#!/usr/bin/env python3
import os
import subprocess
import platform
from pathlib import Path

# Try to import Windows TTS engine as a fallback
try:
    import pyttsx3
except ImportError:
    pyttsx3 = None

FIXTURES_DIR = Path(__file__).resolve().parents[1]

FIXTURES = {
    "hello_how_are_you.wav": "Hello! How are you doing today?",
    "weather.wav": "What's the weather like in Dubai today?",
    "indian_dishes.wav": "Can you recommend a good Indian restaurant nearby?",
    "weather_regression.wav": "What is the best pizza to have in Dubai",
}

def generate_with_gtts():
    """Generate fixtures using Google TTS (requires internet and ffmpeg)."""
    try:
        from gtts import gTTS
        for filename, text in FIXTURES.items():
            out_path = FIXTURES_DIR / filename
            if out_path.exists():
                print(f"  skip (exists): {filename}")
                continue
            
            print(f"  generating (gTTS): {filename}")
            tts = gTTS(text=text, lang="en", slow=False)
            mp3_path = out_path.with_suffix(".mp3")
            tts.save(str(mp3_path))
            
            # Convert MP3 → WAV (16kHz mono, 16-bit PCM)
            # This works on Windows if ffmpeg is in your PATH
            subprocess.run([
                "ffmpeg", "-y", "-i", str(mp3_path),
                "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le",
                str(out_path)
            ], check=True, capture_output=True)
            mp3_path.unlink()
        print("\nDone. Fixtures written to:", FIXTURES_DIR)
    except Exception as e:
        print(f"gTTS failed: {e}")
        generate_with_windows_tts()

def generate_with_windows_tts():
    """Windows fallback: use `pyttsx3` (no internet required)."""
    if pyttsx3 is None:
        print("ERROR: Neither gTTS nor pyttsx3 is installed.")
        print("Please run: pip install gTTS pyttsx3")
        return

    print("Falling back to Windows TTS (pyttsx3)...")
    engine = pyttsx3.init()
    for filename, text in FIXTURES.items():
        out_path = FIXTURES_DIR / filename
        if out_path.exists():
            print(f"  skip (exists): {filename}")
            continue
        print(f"  generating (offline): {filename}")
        # Note: pyttsx3 saves directly to wav on Windows
        engine.save_to_file(text, str(out_path))
        engine.runAndWait()
    print("\nDone. Fixtures written to:", FIXTURES_DIR)

if __name__ == "__main__":
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    
    # Check for ffmpeg
    check_cmd = "where" if platform.system() == "Windows" else "which"
    has_ffmpeg = subprocess.run([check_cmd, "ffmpeg"], capture_output=True).returncode == 0
    
    if has_ffmpeg:
        generate_with_gtts()
    else:
        print("ffmpeg not found. Skipping gTTS and trying offline Windows TTS...")
        generate_with_windows_tts()
