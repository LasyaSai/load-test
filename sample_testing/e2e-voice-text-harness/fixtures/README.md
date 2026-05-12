# fixtures/

WAV audio files used as mic input for voice test cases.

## Required files

| File | Used by |
|------|---------|
| `hello_how_are_you.wav` | `voice_greeting_basic` |
| `whats_the_weather_in_dubai.wav` | `voice_weather_dubai`, `regression_weather_tool_removed_voice` |
| `book_a_table.wav` | `voice_multi_turn_booking` (turn 1) |
| `tomorrow_8pm_for_two.wav` | `voice_multi_turn_booking` (turn 2) |

## Format requirements

- Format: WAV (PCM, 16-bit)
- Sample rate: 16000 Hz
- Channels: Mono
- Duration: typically 2–5 seconds

## Generating fixtures automatically

```bash
# Requires gTTS + ffmpeg (or falls back to macOS `say`)
python fixtures/scripts/generate_fixtures.py
```

## Adding your own

1. Record a voice memo on your phone or Mac.
2. Export as WAV (or convert with `ffmpeg -i input.m4a -ar 16000 -ac 1 output.wav`).
3. Drop the file here.
4. Reference it in your test case YAML: `input_audio: fixtures/your_file.wav`
