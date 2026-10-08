# pyright: reportCallIssue=false
"""Render complete Jsonnet cases before asserting resource relationships."""

import json
import shutil
import subprocess
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
ROOT = TESTS_DIR.parent


class JsonnetTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.jsonnet = shutil.which("jsonnet")
        if cls.jsonnet is None:
            raise RuntimeError(
                "missing Jsonnet executable: install jsonnet or enter nix develop"
            )
        if not (ROOT / "vendor").is_dir():
            raise RuntimeError(
                "missing Jsonnet dependencies: run jb install from the repository root"
            )

    def evaluate_case(self, suite, name):
        fixture = TESTS_DIR / "fixtures" / f"{suite}.libsonnet"
        expression = f"(import {json.dumps(str(fixture))})[{json.dumps(name)}]"
        try:
            return subprocess.run(
                [
                    str(self.jsonnet),
                    "-J",
                    str(ROOT / "vendor"),
                    "-J",
                    str(TESTS_DIR / "imports"),
                    "-e",
                    expression,
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        except subprocess.TimeoutExpired:
            self.fail(f"render {suite}/{name}: Jsonnet exceeded 30 seconds")

    def render_case(self, suite, name):
        result = self.evaluate_case(suite, name)
        self.assertEqual(
            result.returncode, 0, f"render {suite}/{name}:\n{result.stderr}"
        )
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"decode {suite}/{name}: {error}")

    def assert_render_failure(self, suite, name, diagnostic):
        result = self.evaluate_case(suite, name)
        self.assertNotEqual(
            result.returncode, 0, f"{suite}/{name} unexpectedly rendered"
        )
        self.assertIn(diagnostic, result.stderr, f"{suite}/{name}:\n{result.stderr}")
