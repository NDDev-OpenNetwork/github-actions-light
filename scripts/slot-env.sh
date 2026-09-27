#!/usr/bin/env bash
# Shared by install-runner.sh and install-host.sh: the job environment of one
# slot. Sourced, not executed.
#
# Every slot is its own toolchain world. Jobs on different slots of one host
# run at the same time, so a Cargo registry, a rustup home or a Bun global
# directory shared between them is written concurrently and owned by whichever
# job touched a file last. Measured on hosts that shared /usr/local/cargo and
# /usr/local/rustup through an ad-hoc drop-in: Rust cache restores failed with
# `tar: .../usr/local/cargo/registry/...: Permission denied`, rustup installers
# wrote into the shared home, and any job could replace the compiler every
# other organization's jobs used next. The unit already allows writes only
# under /opt/gha-runner/%i; the homes live there too.
#
# The module owns these keys in ${instance_root}/.env and rewrites them on
# every run; any other key in the file is left alone.
MODULE_ENV_KEYS=(LANG PATH CARGO_HOME RUSTUP_HOME BUN_INSTALL)

write_slot_env() {
  local instance_root="$1" user="$2"
  local env_file="${instance_root}/.env" tmp
  touch "${env_file}"
  tmp=$(mktemp)
  grep -vE "^($(IFS='|'; echo "${MODULE_ENV_KEYS[*]}"))=" "${env_file}" > "${tmp}" || true
  {
    echo "LANG=C.UTF-8"
    echo "CARGO_HOME=${instance_root}/.cargo"
    echo "RUSTUP_HOME=${instance_root}/.rustup"
    echo "BUN_INSTALL=${instance_root}/.bun"
    # Slot homes first; the shared /usr/local/cargo/bin stays on the path for
    # the rustup proxies and host-installed cargo tools, read-only.
    echo "PATH=${instance_root}/.cargo/bin:${instance_root}/.bun/bin:${instance_root}/.local/bin:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  } >> "${tmp}"
  install -m 0644 -o "${user}" -g "${user}" "${tmp}" "${env_file}"
  rm -f "${tmp}"
}

# A slot's own rustup home starts empty. Link the host's stable toolchain as its
# default so a job that calls `cargo` without installing a toolchain still has
# one; a job that asks for a version installs it into the slot's own home.
seed_rust_default() {
  local instance_root="$1" user="$2" shared
  command -v rustup >/dev/null 2>&1 || [ -x /usr/local/cargo/bin/rustup ] || return 0
  shared=$(find /usr/local/rustup/toolchains -maxdepth 1 -name "stable-*" 2>/dev/null | head -1)
  [ -n "${shared}" ] || return 0
  sudo -u "${user}" env HOME="${instance_root}" \
    CARGO_HOME="${instance_root}/.cargo" RUSTUP_HOME="${instance_root}/.rustup" \
    PATH="/usr/local/cargo/bin:/usr/bin:/bin" bash -c '
      rustup set auto-self-update disable >/dev/null 2>&1 || true
      rustup toolchain link host-stable "$0" >/dev/null
      rustup default >/dev/null 2>&1 || rustup default host-stable >/dev/null
    ' "${shared}"
}
