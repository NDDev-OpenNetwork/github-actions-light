# Changelog

## 0.1.3

- Every slot is its own toolchain world. `CARGO_HOME`, `RUSTUP_HOME` and
  `BUN_INSTALL` live under the slot (`scripts/slot-env.sh`), with the host's
  stable toolchain linked read-only as the default. Replaces a hand-placed
  drop-in that pointed every slot at one world-writable `/usr/local/cargo` and
  `/usr/local/rustup`: concurrent jobs failed Rust cache restores with
  `Permission denied`, and any job could replace the compiler for the others.
- `install-host.sh` migrates existing slots, removes that drop-in, and starts
  `rollout-slots.sh`, which restarts each slot only when it has no job and then
  makes the shared toolchain directories read-only.
- `unregister-runner.sh` really stops the slot (instance units are not listed
  by `list-unit-files`, so the old guard skipped it) and exits 3 when GitHub
  keeps the registration instead of reporting success.

## 0.1.2

- `scripts/docker-hygiene.sh` and `gha-docker-hygiene.{service,timer}`: daily,
  bounded Docker cleanup for hosts whose slots share the Docker socket. Only
  unused objects are removed; named volumes are never touched, and unused images
  go only above a disk threshold.
- `scripts/install-host.sh`: idempotent host setup (unit files, hygiene timer),
  to run after each module upgrade on a host.

## 0.1.1

- `install-runner.sh` seeds `${PIN_ROOT}/<instance>/.env` with `LANG` and a
  `PATH` covering the slot-local `.local/bin` and `/usr/local/cargo/bin`;
  previously jobs saw only the systemd default PATH and slot-installed tools
  were invisible to `run:` steps.

## 0.1.0

- Pin `actions/runner` 2.337.0 for linux-x64.
- Add systemd instance units for official runner slots.
- Add install and unregister helpers that require a live registration token.
- Extra routing label is `nddev-linux` only.
