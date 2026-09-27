#!/usr/bin/env bash
# Host-level setup shared by every slot. Idempotent; run after each upgrade of
# this module on a host. Registering slots is install-runner.sh's.
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "install-host.sh must run as root" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pin_root=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["layout"]["root"])' "${repo_root}/config/runner-pin.json")
pin_user=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["layout"]["user"])' "${repo_root}/config/runner-pin.json")

for unit in gha-runner@.service gha-runner-docker@.service; do
  install -m 0644 "${repo_root}/systemd/${unit}" "/etc/systemd/system/${unit}"
done

# A hand-placed drop-in pointed every slot at one shared, world-writable
# /usr/local/cargo, /usr/local/rustup and BUN_INSTALL=/usr/local. The slot
# environment below replaces it; nothing else may widen the unit's sandbox.
for legacy in /etc/systemd/system/gha-runner-docker@.service.d/toolchain.conf \
              /etc/systemd/system/gha-runner@.service.d/toolchain.conf; do
  if [[ -f "${legacy}" ]]; then
    rm -f "${legacy}"
    rmdir --ignore-fail-on-non-empty "$(dirname "${legacy}")"
    echo "removed legacy ${legacy}"
  fi
done

# shellcheck source=scripts/slot-env.sh
source "${repo_root}/scripts/slot-env.sh"
for instance_root in "${pin_root}"/*/; do
  instance_root="${instance_root%/}"
  [[ -f "${instance_root}/.runner" ]] || continue
  write_slot_env "${instance_root}" "${pin_user}"
  seed_rust_default "${instance_root}" "${pin_user}"
done

if command -v docker >/dev/null 2>&1; then
  for unit in gha-docker-hygiene.service gha-docker-hygiene.timer; do
    install -m 0644 "${repo_root}/systemd/${unit}" "/etc/systemd/system/${unit}"
  done
fi
systemctl daemon-reload
if command -v docker >/dev/null 2>&1; then
  systemctl enable --now gha-docker-hygiene.timer
  echo "enabled gha-docker-hygiene.timer"
fi

# A running slot reads its .env once, at start. Restart each when it is idle,
# in the background so the caller does not wait for the longest job.
if ! systemctl is-active --quiet gha-slot-rollout.service; then
  systemd-run --unit=gha-slot-rollout --collect "${repo_root}/scripts/rollout-slots.sh"
  echo "started gha-slot-rollout"
fi
