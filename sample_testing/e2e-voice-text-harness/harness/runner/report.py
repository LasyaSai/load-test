"""
report.py — Produces JUnit XML and JSON reports consumed by CI.
"""

import json
from pathlib import Path
from xml.etree import ElementTree as ET


class HarnessReport:
    def __init__(self):
        self.results: list[dict] = []

    def add_result(self, result: dict):
        self.results.append(result)

    @property
    def total(self) -> int:
        return len(self.results)

    @property
    def passed(self) -> int:
        return sum(1 for r in self.results if r["passed"])

    @property
    def failed(self) -> int:
        return self.total - self.passed

    @property
    def all_passed(self) -> bool:
        return self.failed == 0

    def write_junit(self, path: str) -> None:
        """Write JUnit XML compatible with GitHub Actions, Bitrise, Jenkins."""
        suite = ET.Element("testsuite", attrib={
            "name": "E2EVoiceTextHarness",
            "tests": str(self.total),
            "failures": str(self.failed),
            "errors": "0",
        })
        for r in self.results:
            case_el = ET.SubElement(suite, "testcase", attrib={
                "classname": "VoiceTextHarness",
                "name": r["case_id"],
                "time": str(r["duration_ms"] / 1000),
            })
            if not r["passed"]:
                failure = ET.SubElement(case_el, "failure", attrib={
                    "message": r.get("fail_reason", "Assertion failed"),
                    "type": "AssertionError",
                })
                failure.text = (
                    f"Response: {r.get('response_text', '')}\n"
                    f"Judge reasoning: {r.get('judge_reasoning', '')}\n"
                    f"Captured audio: {r.get('captured_audio', '')}"
                )
        tree = ET.ElementTree(suite)
        ET.indent(tree)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        tree.write(path, xml_declaration=True, encoding="utf-8")
        print(f"  JUnit XML → {path}")

    def write_json(self, path: str) -> None:
        report = {
            "summary": {
                "total": self.total,
                "passed": self.passed,
                "failed": self.failed,
            },
            "results": self.results,
        }
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(report, f, indent=2, default=str)
        print(f"  JSON report → {path}")
