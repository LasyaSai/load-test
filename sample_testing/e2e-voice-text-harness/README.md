# E2E Voice & Text Testing Harness

End-to-end test harness for voice and text conversation flows on iOS, with documented extension paths to Android and Web.

## Stack

| Layer | Technology |
|-------|-----------|
| iOS orchestration | Maestro (YAML flows) |
| Voice injection | AVAudioEngine via XCTest bridge |
| Voice capture | AVAudioRecorder speaker tap |
| Transcription | Backend via WebSocket — default: fixture mapping (no API keys); optional STT providers can be added later |
| Semantic verification | OpenRouter chat-completions API (LLM-as-judge, 3-consensus) |
| CI output | JUnit XML + JSON report |
| Test authoring | Plain YAML — no code required |

## Repo Structure

```
e2e-voice-text-harness/
├── app/                        # SwiftUI sample app
│   └── VoiceTextDemo/
│       ├── VoiceTextDemoApp.swift
│       ├── ContentView.swift
│       ├── ChatViewModel.swift
│       ├── AudioManager.swift
│       └── Info.plist
├── harness/
│   ├── audio_bridge/           # XCTest audio injection/capture
│   │   ├── AudioBridgeTests.swift
│   │   └── AudioTestHelper.swift
│   ├── runner/                 # Python orchestrator
│   │   ├── run_tests.py
│   │   ├── test_loader.py
│   │   └── report.py
│   └── verifier/               # WebSocket + OpenRouter LLM-as-judge
│       ├── websocket_client.py
│       └── judge.py
├── test-cases/                 # YAML test cases (non-technical authoring)
│   ├── voice_smoke.yaml
│   ├── text_smoke.yaml
│   └── regression_break.yaml
├── fixtures/                   # WAV audio input files
│   ├── scripts/
│   │   └── generate_fixtures.py
│   └── README.md
├── maestro/                    # Maestro flow files
│   ├── text_chat_flow.yaml
│   └── voice_flow.yaml
├── docs/
│   ├── RUNBOOK.md
│   ├── CI_INTEGRATION.md
│   └── CROSS_PLATFORM.md
├── requirements.txt
└── README.md
```

## Quick Start

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for full setup. TL;DR:

```bash
# 1. Install Python deps
pip install -r requirements.txt

# 2. Set env vars
export OPENROUTER_API_KEY=sk-or-...
export OPENROUTER_MODEL=openrouter/free
export WEBSOCKET_URL=ws://localhost:8000/transcribe  # your backend endpoint

# 3. Boot iOS simulator
xcrun simctl boot "iPhone 15 Pro"

# 4. Build + install sample app
cd app && xcodebuild -scheme VoiceTextDemo -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcrun simctl install booted ./build/VoiceTextDemo.app

# 5. Run smoke suite
python harness/runner/run_tests.py --suite smoke

# 6. Run regression demo (will FAIL deliberately)
python harness/runner/run_tests.py --suite regression
```

## Test Authoring (Non-Technical)

Test cases are plain YAML files in `test-cases/`. Anyone can add a case:

```yaml
- id: my_new_test
  type: text                          # or: voice
  input_text: "What is the capital of France?"
  expected_intent: "Agent answers Paris"
  tags: [smoke]
```

For voice tests, record a .wav in any voice memo app, drop it in `fixtures/`, and reference it:

```yaml
- id: my_voice_test
  type: voice
  input_audio: fixtures/my_recording.wav
  expected_intent: "Agent greets and offers help"
  tags: [smoke, voice]
```

No harness code needs to change. See [docs/RUNBOOK.md](docs/RUNBOOK.md) for full field reference.
