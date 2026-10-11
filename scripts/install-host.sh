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

# Packages the runner and the workflows' setup actions shell out to. A
# minimal host image lacks them: `unzip` is what toolchain actions
# (setup-bun, setup-node's cache path, actions that ship zipped payloads)
# call to unpack, and a job dies at "Prepare all required actions" without
# it. Idempotent; apt is a no-op when the list is already satisfied.
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git tar gzip xz-utils unzip jq python3 rsync \
    make gcc g++ pkg-config libssl-dev protobuf-compiler cmake
fi

# github.com's host keys, global. Workflows write to `$HOME/.ssh/known_hosts`,
# but `ssh` resolves `~` through the passwd entry — `/opt/gha-runner` — not the
# per-slot `HOME` the unit sets, so the only file every slot actually reads is
# this one. Without it a fresh host passes the workflow's keyscan probe and
# then dies at clone on "Host key verification failed".
if command -v ssh-keyscan >/dev/null 2>&1; then
  touch /etc/ssh/ssh_known_hosts
  { ssh-keyscan -T 10 github.com || true; ssh-keyscan -T 10 -p 443 ssh.github.com || true; } \
    >> /etc/ssh/ssh_known_hosts
  sort -u -o /etc/ssh/ssh_known_hosts /etc/ssh/ssh_known_hosts
fi

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
