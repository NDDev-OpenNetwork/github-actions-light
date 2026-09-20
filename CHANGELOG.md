# Changelog

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
