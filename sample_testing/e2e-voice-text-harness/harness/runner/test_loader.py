"""
test_loader.py — Loads and validates YAML test cases.
"""

from pathlib import Path
from typing import Any
import yaml


REQUIRED_FIELDS = {"id", "type", "expected_intent"}


def load_suite(suite_tag: str, repo_root: Path) -> list[dict[str, Any]]:
    """Load all cases tagged with suite_tag from test-cases/ directory."""
    cases_dir = repo_root / "test-cases"
    cases = []
    for yaml_file in sorted(cases_dir.glob("*.yaml")):
        with open(yaml_file) as f:
            raw = yaml.safe_load(f)
        # Support both a list at the top level or a dict with a 'cases' key
        case_list = raw if isinstance(raw, list) else raw.get("cases", [])
        for case in case_list:
            validate_case(case, yaml_file)
            tags = case.get("tags", [])
            if suite_tag in tags or suite_tag == "all":
                cases.append(case)
    if not cases:
        raise ValueError(f"No cases found with tag '{suite_tag}' in {cases_dir}")
    return cases


def load_single_case(case_id: str, repo_root: Path) -> dict[str, Any]:
    """Find and return a single case by ID across all YAML files."""
    cases_dir = repo_root / "test-cases"
    for yaml_file in cases_dir.glob("*.yaml"):
        with open(yaml_file) as f:
            raw = yaml.safe_load(f)
        case_list = raw if isinstance(raw, list) else raw.get("cases", [])
        for case in case_list:
            if case.get("id") == case_id:
                validate_case(case, yaml_file)
                return case
    raise ValueError(f"Case '{case_id}' not found in {cases_dir}")


def validate_case(case: dict, source_file: Path) -> None:
    """Raise ValueError if required fields are missing."""
    missing = REQUIRED_FIELDS - set(case.keys())
    if missing:
        raise ValueError(f"Case in {source_file} missing fields: {missing}\nCase: {case}")
    if case["type"] == "voice" and "input_audio" not in case and "turns" not in case:
        raise ValueError(f"Voice case '{case['id']}' must have 'input_audio' or 'turns'")
    if case["type"] == "text" and "input_text" not in case and "turns" not in case:
        raise ValueError(f"Text case '{case['id']}' must have 'input_text' or 'turns'")
