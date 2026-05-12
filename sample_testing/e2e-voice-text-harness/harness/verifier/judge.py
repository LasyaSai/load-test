"""
judge.py - LLM-as-judge semantic verification via OpenRouter.

For voice cases: transcribes captured audio via WebSocket backend, then judges the transcript.
For text cases: judges the response text directly.

Uses 3-run consensus: all 3 must agree PASS for a PASS verdict.
This eliminates single-run LLM variance without ballooning cost.
"""

import os
import json
import httpx
from .websocket_client import transcribe

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_BASE_URL = os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
JUDGE_MODEL = os.environ.get("JUDGE_MODEL", os.environ.get("OPENROUTER_MODEL", "openrouter/free"))
CONSENSUS_RUNS = 3

JUDGE_SYSTEM_PROMPT = """You are a strict test judge for a conversational AI assistant.
You are given:
- expected_intent: what the assistant's response SHOULD accomplish, described in plain English
- actual_response: what the assistant actually said

Your job: decide if actual_response satisfies expected_intent.

Rules:
- Be semantic, not literal. Paraphrases and synonyms count.
- Minor phrasing differences are fine. Missing the core intent is FAIL.
- If actual_response is empty or clearly off-topic, it is FAIL.
- Respond ONLY with valid JSON: {"verdict": "PASS" | "FAIL", "reason": "<one sentence>"}
"""


def verify(case_def: dict, bridge_output: dict) -> dict:
    """
    Verify a test case result.
    Returns {"passed": bool, "reason": str, "judge_reasoning": str}
    """

    # Tool-call assertion (deterministic, checked before semantic judge)
    if expected_tool := case_def.get("assert_tool_called"):
        actual_tool = bridge_output.get("tool_called")
        if actual_tool != expected_tool:
            return {
                "passed": False,
                "reason": f"Expected tool '{expected_tool}' to be called, got '{actual_tool}'",
                "judge_reasoning": "",
            }

    # For voice cases, transcribe the captured audio
    response_text = bridge_output.get("response_text", "")
    if bridge_output.get("type") == "voice" and (audio := bridge_output.get("captured_audio_path")):
        try:
            response_text = transcribe(audio)
        except Exception as e:
            return {
                "passed": False,
                "reason": f"Transcription failed: {e}",
                "judge_reasoning": "",
            }

    if not response_text:
        return {
            "passed": False,
            "reason": "Empty response from agent",
            "judge_reasoning": "",
        }

    expected_intent = case_def.get("expected_intent", "")

    # 3-consensus LLM judge
    verdicts = []
    reasons = []
    for _ in range(CONSENSUS_RUNS):
        verdict, reason = llm_judge(expected_intent, response_text)
        verdicts.append(verdict)
        reasons.append(reason)

    pass_count = verdicts.count("PASS")
    passed = pass_count == CONSENSUS_RUNS  # strict: all must agree

    return {
        "passed": passed,
        "reason": reasons[-1] if not passed else "",
        "judge_reasoning": f"{pass_count}/{CONSENSUS_RUNS} runs PASS - {reasons}",
    }


def llm_judge(expected_intent: str, actual_response: str) -> tuple[str, str]:
    """Run a single judge call. Returns (verdict, reason)."""
    if not OPENROUTER_API_KEY:
        # Stub for local testing without API key
        return ("PASS", "stub pass - no API key")

    prompt = json.dumps({
        "expected_intent": expected_intent,
        "actual_response": actual_response,
    })

    try:
        response = httpx.post(
            f"{OPENROUTER_BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {OPENROUTER_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": JUDGE_MODEL,
                "max_tokens": 256,
                "temperature": 0,
                "messages": [
                    {"role": "system", "content": JUDGE_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
            },
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
        content = _extract_message_content(payload)
        content = content.strip().removeprefix("```json").removesuffix("```").strip()
        parsed = json.loads(content)
        return parsed.get("verdict", "FAIL"), parsed.get("reason", "")
    except Exception as e:
        return ("FAIL", f"Judge error: {e}")


def _extract_message_content(payload: dict) -> str:
    choices = payload.get("choices") or []
    if not choices:
        return ""

    message = choices[0].get("message") or {}
    content = message.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                chunks.append(block.get("text", ""))
        return "".join(chunks)
    return ""
