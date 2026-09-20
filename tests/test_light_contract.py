#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_contract():
    path = ROOT / "scripts/light_contract.py"
    spec = importlib.util.spec_from_file_location("light_contract", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class LightContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = load_contract()

    def test_pin_matches_unit_user(self) -> None:
        pin = self.contract.load_pin()
        self.assertEqual(pin["layout"]["user"], "gha-runner")
        self.assertEqual(pin["labels"]["required"], ["nddev-linux"])

    def test_install_script_requires_token_and_verifies_digest(self) -> None:
        text = (ROOT / "scripts/install-runner.sh").read_text(encoding="utf-8")
        self.assertIn("RUNNER_TOKEN", text)
        self.assertIn("sha256sum -c", text)
        self.assertIn("--unattended", text)
        self.assertNotIn("garm", text.lower())

    def test_install_script_seeds_job_path(self) -> None:
        text = (ROOT / "scripts/install-runner.sh").read_text(encoding="utf-8")
        self.assertIn('/.env', text)
        self.assertIn("grep -q '^PATH='", text)
        self.assertIn("/.local/bin", text)
        self.assertIn("/usr/local/cargo/bin", text)

    def test_public_ci_is_hosted(self) -> None:
        self.contract.assert_public_ci()

    def test_full_contract(self) -> None:
        self.contract.main()


if __name__ == "__main__":
    unittest.main()
