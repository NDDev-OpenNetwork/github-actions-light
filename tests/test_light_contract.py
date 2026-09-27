#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
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
        install = (ROOT / "scripts/install-runner.sh").read_text(encoding="utf-8")
        env = (ROOT / "scripts/slot-env.sh").read_text(encoding="utf-8")
        self.assertIn("write_slot_env", install)
        self.assertIn("/.env", env)
        self.assertIn("/.local/bin", env)
        self.assertIn("/usr/local/cargo/bin", env)

    def test_host_hygiene_removes_only_what_no_job_uses(self) -> None:
        self.contract.assert_host_hygiene()
        text = (ROOT / "scripts/docker-hygiene.sh").read_text(encoding="utf-8")
        self.assertIn('docker container prune -f --filter "until=24h"', text)
        self.assertIn("docker volume prune -f\n", text)
        self.assertIn("docker image prune -f\n", text)

    def test_host_hygiene_refuses_named_volume_removal(self) -> None:
        read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")  # noqa: E731
        parts = [
            read("scripts/docker-hygiene.sh"),
            read("systemd/gha-docker-hygiene.service"),
            read("systemd/gha-docker-hygiene.timer"),
            read("scripts/install-host.sh"),
        ]
        self.assertEqual(self.contract.hygiene_violations(*parts), [])
        broken = [parts[0].replace("docker volume prune -f", "docker volume prune -a -f"), *parts[1:]]
        self.assertTrue(self.contract.hygiene_violations(*broken))
        unbounded = [parts[0].replace('disk_prune_percent', 'x'), *parts[1:]]
        self.assertTrue(self.contract.hygiene_violations(*unbounded))

    def test_slot_env_owns_its_keys_and_keeps_the_rest(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            slot = os.path.join(root, "example-org-1")
            os.mkdir(slot)
            env = os.path.join(slot, ".env")
            with open(env, "w") as f:
                f.write("PATH=/old\nCARGO_HOME=/usr/local/cargo\nCUSTOM=kept\n")
            user = subprocess.check_output(["id", "-un"], text=True).strip()
            script = f'source "{ROOT}/scripts/slot-env.sh"; write_slot_env "$0" "$1"'
            for _ in range(2):  # idempotent
                subprocess.run(["bash", "-c", script, slot, user], check=True)
            lines = open(env).read().splitlines()
        self.assertIn("CUSTOM=kept", lines)
        self.assertIn(f"CARGO_HOME={slot}/.cargo", lines)
        self.assertIn(f"RUSTUP_HOME={slot}/.rustup", lines)
        self.assertIn(f"BUN_INSTALL={slot}/.bun", lines)
        paths = [line for line in lines if line.startswith("PATH=")]
        self.assertEqual(len(paths), 1)
        self.assertTrue(paths[0].startswith(f"PATH={slot}/.cargo/bin:"))
        self.assertNotIn("CARGO_HOME=/usr/local/cargo", lines)

    def test_slot_isolation_contract(self) -> None:
        self.contract.assert_slot_isolation()

    def test_public_ci_is_hosted(self) -> None:
        self.contract.assert_public_ci()

    def test_full_contract(self) -> None:
        self.contract.main()


if __name__ == "__main__":
    unittest.main()
