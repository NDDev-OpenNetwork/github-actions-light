#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST_FACTS = (
    "10.110.",
    "164.92.",
    "209.38.",
    "gha-services",
    "gha-runner-1",
    "gha-runner-2",
    "nddev-estate-static",
    "nddev-linux-fast",
    "nddev-linux-standard",
    "nddev-linux-integration",
)
PRIVATE_ORGS = (
    "NDDev-it-com",
    "My-Attention-AI-Inc",
    "NDDev-Platform",
)
CONTRACT_FILES = {"light_contract.py", "test_light_contract.py"}


def fail(message: str) -> None:
    raise SystemExit(message)


def load_pin() -> dict:
    pin = json.loads((ROOT / "config/runner-pin.json").read_text(encoding="utf-8"))
    if pin.get("schema") != "nddev-actions-runner-pin/v1":
        fail("unexpected runner pin schema")
    runner = pin["runner"]
    sha = runner["sha256"]
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        fail("runner pin sha256 must be lowercase hex")
    if runner["version"] not in runner["archive"] or runner["version"] not in runner["url"]:
        fail("runner pin version does not match archive/url")
    if pin["labels"]["required"] != ["nddev-linux"]:
        fail("required extra label must be exactly nddev-linux")
    return pin


def assert_public_ci() -> None:
    workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    if "runs-on: ubuntu-latest" not in workflow:
        fail("public CI must use ubuntu-latest")
    if "self-hosted" in workflow or "nddev-linux" in workflow:
        fail("public CI must not use self-hosted labels")
    if "pull_request_target" in workflow or "secrets:" in workflow:
        fail("public CI trust boundary drifted")


def assert_units(pin: dict) -> None:
    unit = (ROOT / "systemd/gha-runner@.service").read_text(encoding="utf-8")
    docker = (ROOT / "systemd/gha-runner-docker@.service").read_text(encoding="utf-8")
    user = pin["layout"]["user"]
    for content, name in ((unit, "gha-runner@.service"), (docker, "gha-runner-docker@.service")):
        if f"User={user}" not in content:
            fail(f"{name} must run as {user}")
        if "ExecStart=/opt/gha-runner/%i/run.sh" not in content:
            fail(f"{name} must start the official run.sh")
        if "garm" in content.lower() or "incus" in content.lower():
            fail(f"{name} contains retired control-plane names")
    if "SupplementaryGroups=docker" not in docker:
        fail("docker unit must join the docker group")
    if "SupplementaryGroups=docker" in unit:
        fail("non-docker unit must not join the docker group")


def assert_scripts() -> None:
    install = (ROOT / "scripts/install-runner.sh").read_text(encoding="utf-8")
    unregister = (ROOT / "scripts/unregister-runner.sh").read_text(encoding="utf-8")
    for content, name in ((install, "install-runner.sh"), (unregister, "unregister-runner.sh")):
        if "RUNNER_TOKEN" not in content:
            fail(f"{name} must require RUNNER_TOKEN")
        if "echo \"${RUNNER_TOKEN" in content or "echo $RUNNER_TOKEN" in content:
            fail(f"{name} logs the registration token")
        if "sha256sum -c" not in content and name == "install-runner.sh":
            fail("install-runner.sh must verify the archive digest")


def assert_no_estate_facts() -> None:
    tracked = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(".git/") or "/__pycache__/" in rel or rel.endswith(".pyc"):
            continue
        tracked.append(path)
    for path in tracked:
        if path.name in CONTRACT_FILES:
            continue
        raw = path.read_text(encoding="utf-8", errors="replace")
        lower = raw.lower()
        for needle in HOST_FACTS:
            if needle.lower() in lower:
                fail(f"{path.relative_to(ROOT)} contains estate token {needle!r}")
        if "RUNNER_TOKEN=" in raw and path.suffix == ".sh":
            fail(f"{path.relative_to(ROOT)} assigns RUNNER_TOKEN")
        for org in PRIVATE_ORGS:
            if org in raw:
                fail(f"{path.relative_to(ROOT)} names a private organization")


def assert_actions_catalog() -> None:
    catalog = _load_catalog()
    workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    uses = re.findall(r"uses:\s+([^\s@]+)@([0-9a-f]{40})", workflow)
    by_name = {item["name"]: item for item in catalog["actions"]}
    if not uses:
        fail("ci workflow has no pinned actions")
    for name, sha in uses:
        entry = by_name.get(name)
        if entry is None:
            fail(f"undeclared action {name}")
        if entry["sha"] != sha:
            fail(f"{name} sha drifted from catalog")
        if entry["version"] not in workflow:
            fail(f"{name} catalog version is missing from ci.yml")


def _load_catalog() -> dict:
    # Tiny YAML subset: the catalog is a short list of name/sha/version maps.
    text = (ROOT / "catalog/actions.yml").read_text(encoding="utf-8")
    actions: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("- name:"):
            if current:
                actions.append(current)
            current = {"name": line.split(":", 1)[1].strip().strip('"')}
        elif line.startswith("sha:") and current:
            current["sha"] = line.split(":", 1)[1].strip().strip('"')
        elif line.startswith("version:") and current:
            current["version"] = line.split(":", 1)[1].strip().strip('"')
    if current:
        actions.append(current)
    if not actions:
        fail("catalog/actions.yml has no actions")
    return {"actions": actions}


def main() -> None:
    pin = load_pin()
    assert_public_ci()
    assert_units(pin)
    assert_scripts()
    assert_no_estate_facts()
    assert_actions_catalog()
    print("github-actions-light contract ok")


if __name__ == "__main__":
    main()
