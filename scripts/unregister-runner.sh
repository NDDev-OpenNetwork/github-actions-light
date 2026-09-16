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
for unit in "gha-runner@${instance}.service" "gha-runner-docker@${instance}.service"; do
  if systemctl list-unit-files "${unit}" >/dev/null 2>&1; then
    systemctl disable --now "${unit}" >/dev/null 2>&1 || true
  fi
done

if [[ -x "${instance_root}/config.sh" ]]; then
  cd "${instance_root}"
  sudo -u "${PIN_USER}" ./config.sh remove --token "${RUNNER_TOKEN}" --unattended || true
fi

if [[ "${purge}" -eq 1 ]]; then
  rm -rf "${instance_root}"
fi
echo "unregistered ${instance}"
