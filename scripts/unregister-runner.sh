#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: unregister-runner.sh --instance NAME [--purge]

Environment:
  RUNNER_TOKEN   short-lived GitHub registration token (required, never logged)
EOF
}

instance=""
purge=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)
      instance="${2:-}"
      shift 2
      ;;
    --purge)
      purge=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "unregister-runner.sh must run as root" >&2
  exit 2
fi
if [[ -z "${instance}" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "${instance}" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "instance must be a lowercase hostname-safe name" >&2
  exit 2
fi
if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  echo "RUNNER_TOKEN is required" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
eval "$(python3 - "${repo_root}/config/runner-pin.json" <<'PY'
import json, shlex, sys
pin = json.loads(open(sys.argv[1], encoding="utf-8").read())
print("PIN_USER=" + shlex.quote(pin["layout"]["user"]))
print("PIN_ROOT=" + shlex.quote(pin["layout"]["root"]))
PY
)"

instance_root="${PIN_ROOT}/${instance}"
# `list-unit-files` does not list template instances, so guarding on it left
# the slot running. Disable unconditionally; an absent unit is not an error.
for unit in "gha-runner@${instance}.service" "gha-runner-docker@${instance}.service"; do
  systemctl disable --now "${unit}" >/dev/null 2>&1 || true
  systemctl reset-failed "${unit}" >/dev/null 2>&1 || true
done

removed=0
if [[ -x "${instance_root}/config.sh" ]]; then
  cd "${instance_root}"
  if sudo -u "${PIN_USER}" ./config.sh remove --token "${RUNNER_TOKEN}" --unattended; then
    removed=1
  fi
fi

if [[ "${purge}" -eq 1 ]]; then
  rm -rf "${instance_root}"
fi
if [[ "${removed}" -ne 1 ]]; then
  # A repository that moved answers the saved URL with 404, so the
  # registration outlives the slot. Say so; the caller deletes it by id.
  echo "stopped ${instance} locally, but GitHub still holds its registration" >&2
  exit 3
fi
echo "unregistered ${instance}"
