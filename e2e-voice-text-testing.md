# Assignment: Automated End-to-End Testing — Voice and Text

## Description

Today, we have no automated way to verify that voice and text features still work before a release. Manual smoke-testing across iOS, Android, and web is slow, inconsistent, and skips edge cases.

You will evaluate approaches for an end-to-end testing harness that exercises both voice and text conversations against a real mobile or web client, then build a working harness for iOS plus a documented path to Android and web.

### Goals
- Catch regressions on voice and text flows before a release goes out.
- Authoring and editing test cases is practical for **non-technical people**. Other authoring options are acceptable if adoption stays low-friction.
- Voice tests use **real audio**: audio injected into the mic input, audio captured at the speaker output. Simulating the voice path with text is not acceptable.
- The chosen approach extends cleanly to web and Android even though the demo runs only on iOS.

### Out of Scope
- Actual CI integration on our pipeline. Document a clear integration methodology; you do not need to wire it up.
- Test-coverage breadth. The demo needs only enough cases to demonstrate the harness, not full coverage.

---

## Phase 1 — Evaluation

Survey approaches. Example directions:
- Mobile E2E frameworks (Detox, Appium, Maestro, XCUITest / Espresso, cloud device farms).
- Web E2E frameworks (Playwright, Cypress, etc.) for the same conversation flows.
- Voice-specific testing: how to inject audio into the mic, capture TTS audio output, transcribe it, and assert on it.
- Verification strategies for non-deterministic LLM outputs (LLM-as-judge, tool-call assertions, semantic match, latency budgets).
- Authoring formats and tooling for non-technical authors (record-and-replay, declarative cases, low-code UI).
- Anything else you can come up with.

For each, assess:
- Strength of coverage — what kinds of flows it can and cannot test.
- Stability and flake rate; CI-friendliness.
- Voice support: real audio in and out, latency assertions, barge-in.
- Cross-platform reach: does the same harness or pattern extend to web and Android?
- Authoring experience for a non-technical author.
- Cost and operational burden.

Cite existing prior art, including any open-source harnesses for voice-agent testing.

---

## Phase 2 — Build

Build a working harness for **iOS** that:
- Runs on an iOS simulator or device against a sample app you stand up.
- Executes test cases covering both text-only and voice conversations.
- For voice: injects real audio into the mic and captures the agent's audio output, then asserts on the captured response.
- Includes verification that is robust to LLM non-determinism (semantic check, not exact-match where inappropriate).
- Stores test cases in a format your chosen authoring approach supports.
- Produces clear pass/fail output suitable for a CI runner.

You decide the sample app, the voice and text scenarios, and the verification rules. They must collectively show that the harness catches a regression — including at least one deliberately introduced break.

---

## Demo Scenario
A live run of the harness against the sample iOS app, executing voice and text test cases end-to-end. You decide which cases to run; together they must demonstrate real audio injection and capture, semantic verification of LLM outputs, and a deliberately introduced regression being caught.

---

## Requirements

### Tech
- **Demo target:** iOS simulator or device.
- **Voice:** real audio injection at the mic and real audio capture at the speaker.
- **Sample app:** any minimal app with voice and text chat, sufficient to exercise the harness.

### Functional
- Test cases can be added and edited without writing harness code from scratch each time.
- Authoring experience is practical for a non-technical author. If your chosen approach falls short of fully non-technical, document the trade-off.
- Verification is robust to LLM non-determinism — assertions describe the expected outcome semantically, not by exact string match where that would be brittle.
- Pass/fail output is machine-readable and CI-consumable.
- The harness pattern extends to web and Android. Document what changes for each, even though you do not implement them.

---

## Deliverables

1. **Private GitHub repository** containing:
   - Evaluation report (Phase 1).
   - Working iOS harness, sample app, and test cases (Phase 2).
   - Setup runbook so anyone can reproduce the harness locally.

2. **Evaluation report**
   - Approaches surveyed.
   - Comparison against the criteria above.
   - Recommendation with justification.
   - Documented authoring experience for a non-technical author.
   - Cross-platform extension plan: what changes for web, what changes for Android.
   - CI integration methodology: how the harness slots into a release pipeline (when it runs, what it gates, how failures are surfaced), infrastructure assumptions (device farm, self-hosted runners, hosted simulator services), estimated runtime, and flake-management strategy.

3. **Presentation deck** (~8 to 10 minutes + Q&A)
   - Approaches surveyed and the chosen one.
   - How the harness handles voice (real audio path).
   - How verification handles LLM non-determinism.
   - Authoring experience for non-technical authors.
   - Cross-platform extension plan.
   - CI integration methodology.
   - What you learned.

4. **Live demo** (~3 to 5 minutes, after the presentation)
   - Voice and text test cases running end-to-end on iOS.
   - At least one regression caught by the harness.
   - A test case being added or edited via the chosen authoring experience.

---

## Timeline

You have **one week** from the start date. The presentation is delivered on day 7.

---

## Evaluation Criteria

| Area | Weight |
|------|--------|
| Evaluation depth (approaches surveyed, fit to criteria) | 15% |
| Voice testing rigor (real audio in and out, semantic verification) | 20% |
| Demo execution (iOS harness runs end-to-end, regression caught) | 15% |
| Authoring experience for non-technical authors | 15% |
| Cross-platform extension plan and CI integration methodology | 15% |
| Presentation (clarity, demo, handling questions) | 20% |

---

## Stretch Goals

- **Visual regression for widgets:** the harness verifies that rendered widgets look right, not just that the right tool was called.
- **Latency budgets:** per-turn latency assertions (end-of-user-utterance to start-of-agent-audio), failing a test when a budget is exceeded.
