#!/usr/bin/env python3
"""
run_tests.py — Main harness runner.

Usage:
    python run_tests.py --suite smoke
    python run_tests.py --suite regression
    python run_tests.py --case voice_greeting_basic
    python run_tests.py --suite smoke --output reports/run.xml
"""

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path
import shutil
from test_loader import load_suite, load_single_case
from report import HarnessReport

REPO_ROOT = Path(__file__).resolve().parents[2]
XCODEBUILD = "xcodebuild"
SCHEME = "VoiceTextDemo"
TEST_TARGET = "AudioBridgeTests"
SIMULATOR = os.environ.get("IOS_SIMULATOR", "iPhone 16")
TMP_DIR = Path("/tmp/harness_outputs")
MAX_RETRIES = 2


def main():
    parser = argparse.ArgumentParser(description="E2E Voice+Text Harness Runner")
    parser.add_argument("--suite", help="Suite tag to run (e.g. smoke, regression)")
    parser.add_argument("--case", help="Run a single case by ID")
    parser.add_argument("--output", default="reports/report.xml", help="JUnit XML output path")
    parser.add_argument("--json-output", default="reports/report.json", help="JSON report output path")
    args = parser.parse_args()

    TMP_DIR.mkdir(parents=True, exist_ok=True)

    if args.case:
        cases = [load_single_case(args.case, REPO_ROOT)]
    elif args.suite:
        cases = load_suite(args.suite, REPO_ROOT)
    else:
        print("ERROR: specify --suite or --case", file=sys.stderr)
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"  E2E Harness — {len(cases)} case(s)")
    print(f"  Simulator: {SIMULATOR}")
    print(f"{'='*60}\n")

    report = HarnessReport()

    for case_def in cases:
        result = run_case_with_retry(case_def)
        report.add_result(result)
        status = "✅ PASS" if result["passed"] else "❌ FAIL"
        print(f"  {status}  {case_def['id']}  ({result['duration_ms']}ms)")
        if not result["passed"]:
            print(f"         Reason: {result.get('fail_reason', 'unknown')}")

    print(f"\n{'='*60}")
    print(f"  Results: {report.passed}/{report.total} passed")
    print(f"{'='*60}\n")

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.json_output).parent.mkdir(parents=True, exist_ok=True)
    report.write_junit(args.output)
    report.write_json(args.json_output)

    sys.exit(0 if report.all_passed else 1)


def run_case_with_retry(case_def: dict) -> dict:
    for attempt in range(1, MAX_RETRIES + 2):
        result = run_case(case_def)
        if result["passed"] or attempt > MAX_RETRIES:
            result["attempts"] = attempt
            return result
        print(f"    ↻ Retry {attempt}/{MAX_RETRIES} for {case_def['id']}")
    return result  # unreachable but satisfies type checker


def run_case(case_def: dict) -> dict:
    run_id = uuid.uuid4().hex[:8]
    output_path = str(TMP_DIR / f"{case_def['id']}_{run_id}")
    start = time.time()

    env = {
        **os.environ,
        "CASE_TYPE": case_def.get("type", "text"),
        "CASE_OUTPUT_PATH": output_path,
        "OPENROUTER_API_KEY": os.environ.get("OPENROUTER_API_KEY", ""),
        "OPENROUTER_BASE_URL": os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"),
        "OPENROUTER_MODEL": os.environ.get("OPENROUTER_MODEL", "openrouter/free"),
        "WEBSOCKET_URL": os.environ.get("WEBSOCKET_URL", ""),
    }

    if case_def.get("type") == "text":
        env["CASE_INPUT_TEXT"] = case_def.get("input_text", "")
    elif case_def.get("type") == "voice":
        audio_path = str(REPO_ROOT / case_def.get("input_audio", ""))
        env["CASE_INPUT_AUDIO"] = audio_path

    if case_def.get("regression_break"):
        env["REGRESSION_BREAK_TOOL_CALL"] = "YES"

    # Run XCTest bridge
    xcode_result = run_xctest(env)
    duration_ms = int((time.time() - start) * 1000)

    if xcode_result["returncode"] != 0:
        return {
            "case_id": case_def["id"],
            "passed": False,
            "fail_reason": f"XCTest failed: {xcode_result['stderr'][-500:]}",
            "duration_ms": duration_ms,
        }

    # Load output written by XCTest
    output_file = Path(output_path + ".json")
    if not output_file.exists():
        return {
            "case_id": case_def["id"],
            "passed": False,
            "fail_reason": "No output file written by XCTest bridge",
            "duration_ms": duration_ms,
        }

    with open(output_file) as f:
        bridge_output = json.load(f)

    # Run verifier
    from verifier.judge import verify
    verification = verify(case_def, bridge_output)

    # Latency budget check (non-blocking by default)
    latency_ok = True
    if budget := case_def.get("latency_budget_ms"):
        latency_ok = duration_ms <= budget
        if not latency_ok:
            print(f"    ⚠ Latency budget exceeded: {duration_ms}ms > {budget}ms")

    passed = verification["passed"] and (latency_ok or not case_def.get("latency_budget_blocking", False))

    return {
        "case_id": case_def["id"],
        "passed": passed,
        "fail_reason": verification.get("reason") if not passed else None,
        "response_text": bridge_output.get("response_text", ""),
        "judge_reasoning": verification.get("judge_reasoning", ""),
        "duration_ms": duration_ms,
        "latency_ok": latency_ok,
        "captured_audio": bridge_output.get("captured_audio_path"),
    }
def run_xctest(env: dict) -> dict:


    xcresult_path = TMP_DIR / "xcresult"
    if xcresult_path.exists():
        shutil.rmtree(xcresult_path)

    if "e2e-voice-text-harness" in os.getcwd():
        project_dir = Path.cwd() / "App"
    else:
        project_dir = REPO_ROOT / "sample_testing/e2e-voice-text-harness/App"

    cmd = [
        XCODEBUILD, "test",
        "-scheme", SCHEME,
        "-destination", f"platform=iOS Simulator,name={SIMULATOR}",
        "-only-testing", f"{TEST_TARGET}/AudioBridgeTests/testRunCase",
        "-resultBundlePath", str(xcresult_path)
    ]

    result = subprocess.run(
        cmd, 
        capture_output=True, 
        text=True, 
        env=env, 
        cwd=str(project_dir), 
        timeout=180
    )
    
    return {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
if __name__ == "__main__":
    main()
