#!/usr/bin/env bash
# Host-level setup shared by every slot. Idempotent; run after each upgrade of
# this module on a host. Slots themselves are install-runner.sh's.
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "install-host.sh must run as root" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for unit in gha-runner@.service gha-runner-docker@.service; do
  install -m 0644 "${repo_root}/systemd/${unit}" "/etc/systemd/system/${unit}"
done
if command -v docker >/dev/null 2>&1; then
  for unit in gha-docker-hygiene.service gha-docker-hygiene.timer; do
    install -m 0644 "${repo_root}/systemd/${unit}" "/etc/systemd/system/${unit}"
  done
  systemctl daemon-reload
  systemctl enable --now gha-docker-hygiene.timer
  echo "enabled gha-docker-hygiene.timer"
else
  systemctl daemon-reload
fi
