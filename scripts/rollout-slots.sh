#!/usr/bin/env bash
# Restart every slot once, each only when it has no job, so a changed .env
# or unit takes effect without killing work. Then make the host's shared
# toolchain directories read-only: once every slot runs with its own homes,
# nothing should write there.
set -Euo pipefail

deadline=$(( $(date +%s) + ${GHA_ROLLOUT_SECONDS:-7200} ))
mapfile -t pending < <(systemctl list-units 'gha-runner*@*.service' --state=running --plain --no-legend | awk '{print $1}')
echo "rollout: ${#pending[@]} slot(s)"

idle() {
  local inst="${1#*@}"
  inst="${inst%.service}"
  ! pgrep -f "/opt/gha-runner/${inst}/bin/Runner.Worker" >/dev/null
}

while ((${#pending[@]})); do
  left=()
  for unit in "${pending[@]}"; do
    # Twice, a second apart: a job being handed over has a Worker within it.
    if idle "${unit}" && sleep 1 && idle "${unit}"; then
      systemctl restart "${unit}" && echo "rollout: restarted ${unit}"
    else
      left+=("${unit}")
    fi
  done
  pending=("${left[@]}")
  ((${#pending[@]})) || break
  if (( $(date +%s) >= deadline )); then
    echo "rollout: deadline reached, still busy: ${pending[*]}; shared toolchains left writable" >&2
    exit 1
  fi
  sleep 15
done

for shared in /usr/local/cargo /usr/local/rustup; do
  if [[ -d "${shared}" ]]; then
    chown -R root:root "${shared}"
    chmod -R go-w "${shared}"
    echo "rollout: ${shared} is read-only for slots"
  fi
done
