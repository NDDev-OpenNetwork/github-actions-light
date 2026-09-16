#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: install-runner.sh --instance NAME --url GITHUB_URL [--name RUNNER_NAME] [--docker]

Environment:
  RUNNER_TOKEN   short-lived GitHub registration token (required, never logged)
EOF
}

instance=""
url=""
runner_name=""
with_docker=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)
      instance="${2:-}"
      shift 2
      ;;
    --url)
      url="${2:-}"
      shift 2
      ;;
    --name)
      runner_name="${2:-}"
      shift 2
      ;;
    --docker)
      with_docker=1
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
  echo "install-runner.sh must run as root" >&2
  exit 2
fi
if [[ -z "${instance}" || -z "${url}" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "${instance}" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "instance must be a lowercase hostname-safe name" >&2
  exit 2
fi
if [[ ! "${url}" =~ ^https://github\.com/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$ ]]; then
  echo "url must be https://github.com/<owner> or https://github.com/<owner>/<repo>" >&2
  exit 2
fi
if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  echo "RUNNER_TOKEN is required" >&2
  exit 2
fi

runner_name="${runner_name:-${instance}}"
if [[ ! "${runner_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]]; then
  echo "runner name is invalid" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pin_file="${repo_root}/config/runner-pin.json"
if [[ ! -f "${pin_file}" ]]; then
  echo "missing ${pin_file}" >&2
  exit 2
fi

eval "$(python3 - "${pin_file}" <<'PY'
import json, shlex, sys
pin = json.loads(open(sys.argv[1], encoding="utf-8").read())
runner = pin["runner"]
layout = pin["layout"]
labels = ",".join(pin["labels"]["required"])
keys = {
    "PIN_URL": runner["url"],
    "PIN_ARCHIVE": runner["archive"],
    "PIN_SHA256": runner["sha256"],
    "PIN_USER": layout["user"],
    "PIN_ROOT": layout["root"],
    "PIN_LABELS": labels,
}
for key, value in keys.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"

if [[ "${PIN_SHA256}" =~ [^0-9a-f] ]] || [[ "${#PIN_SHA256}" -ne 64 ]]; then
  echo "runner pin sha256 is not a lowercase hex digest" >&2
  exit 2
fi

install -d -m 0755 "${PIN_ROOT}"
if ! id -u "${PIN_USER}" >/dev/null 2>&1; then
  useradd --system --home "${PIN_ROOT}" --shell /usr/sbin/nologin "${PIN_USER}"
fi
if [[ "${with_docker}" -eq 1 ]]; then
  if ! getent group docker >/dev/null; then
    echo "docker group is missing; install Docker before --docker" >&2
    exit 2
  fi
  usermod -aG docker "${PIN_USER}"
fi

instance_root="${PIN_ROOT}/${instance}"
install -d -m 0750 -o "${PIN_USER}" -g "${PIN_USER}" "${instance_root}"
archive_path="${instance_root}/${PIN_ARCHIVE}"

tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
curl -fsSL --proto '=https' --tlsv1.2 -o "${tmp}" "${PIN_URL}"
echo "${PIN_SHA256}  ${tmp}" | sha256sum -c -
mv "${tmp}" "${archive_path}"
trap - EXIT

tar -xzf "${archive_path}" -C "${instance_root}"
rm -f "${archive_path}"
chown -R "${PIN_USER}:${PIN_USER}" "${instance_root}"

install -m 0644 "${repo_root}/systemd/gha-runner@.service" /etc/systemd/system/gha-runner@.service
install -m 0644 "${repo_root}/systemd/gha-runner-docker@.service" /etc/systemd/system/gha-runner-docker@.service
systemctl daemon-reload

cd "${instance_root}"
sudo -u "${PIN_USER}" ./config.sh --unattended --replace \
  --url "${url}" \
  --token "${RUNNER_TOKEN}" \
  --name "${runner_name}" \
  --labels "${PIN_LABELS}" \
  --work "_work"

unit="gha-runner@${instance}.service"
if [[ "${with_docker}" -eq 1 ]]; then
  unit="gha-runner-docker@${instance}.service"
fi
systemctl enable --now "${unit}"
echo "enabled ${unit}"
