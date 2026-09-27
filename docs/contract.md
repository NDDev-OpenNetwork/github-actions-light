# Contract

Status: accepted for the 0.1.0 install surface.

## Runner identity

The only extra label this product applies is `nddev-linux`. GitHub adds
`self-hosted`, `Linux`, and `X64`. Callers must not invent a second private
taxonomy in this repository.

## Trust

Persistent slots are for trusted internal private repositories. Public and
fork pull-request jobs stay on GitHub-hosted runners. `--docker` shares the
host Docker socket with the slot; that is a trust decision, not a default.

## Registration

Each systemd instance is one concurrent GitHub job. Organization registrations
serve one organization. Personal repositories require repository registrations.
This product does not create a cross-account pool.

## Job environment

Jobs inherit the runner process environment plus `${PIN_ROOT}/<instance>/.env`.
The module owns five keys there and rewrites them on every install:

| Key | Value |
| --- | --- |
| `LANG` | `C.UTF-8` |
| `CARGO_HOME` | `${PIN_ROOT}/<instance>/.cargo` |
| `RUSTUP_HOME` | `${PIN_ROOT}/<instance>/.rustup` |
| `BUN_INSTALL` | `${PIN_ROOT}/<instance>/.bun` |
| `PATH` | the three homes' bin directories, the slot's `.local/bin`, `/usr/local/cargo/bin`, then the system defaults |

Other keys in the file are kept. **Every slot is its own toolchain world.**
Slots on one host run jobs at the same time, and the unit allows writes only
under `${PIN_ROOT}/<instance>`, so a registry, rustup home or Bun global
directory shared between slots is a race and a cross-tenant write path. A
slot's rustup home starts with the host's stable toolchain linked as
`host-stable`, read-only, so a job that calls `cargo` directly works. A job that
asks for a version installs it into its own slot. `/usr/local/cargo/bin` stays
on the path, read-only, for the rustup proxies and host-installed cargo tools.

A slot reads its `.env` once, at start. `install-host.sh` rewrites every slot's
environment and starts `gha-slot-rollout`, which restarts each slot only when it
has no job. Once all have restarted it makes `/usr/local/cargo` and
`/usr/local/rustup` read-only for the slots.

## Host hygiene

Slots started with `--docker` share the host's Docker socket, so their jobs
leave stopped containers, anonymous service volumes, BuildKit cache and images
on the host, and nothing else removes them. `scripts/install-host.sh` installs
`gha-docker-hygiene.timer`, which runs `scripts/docker-hygiene.sh` daily. That
script removes only what no container is using: stopped containers older than
a day, unreferenced anonymous volumes, dangling images, and build cache beyond
`GHA_BUILD_CACHE_MAX` (default 20GB). It removes unused images older than
`GHA_IMAGE_MAX_AGE` (default 168h) only once the root filesystem is at
`GHA_DISK_PRUNE_PERCENT` (default 70) or more, so a host with room keeps its
pulls. Named volumes are never removed. `install-host.sh` is idempotent: run it
after every upgrade of this module on a host.

## Reinstall

`install-runner.sh` on an instance that is already registered under the same
name and scope repairs it. It refreshes the unit files, the job environment and
the enablement, and neither downloads nor reconfigures, because GitHub's
`config.sh` refuses a configured runner and re-extracting would overwrite the
binaries of a running slot. A different registration in the same directory is
refused until it is unregistered.

## Removal

`unregister-runner.sh` always stops and disables the slot's unit, then removes
the registration. If GitHub refuses the removal, it exits 3 and says the
registration remains, for example for a repository that moved, whose saved URL
now answers 404. The caller then deletes the registration by id.

## Failure

A missing, expired, or replayed registration token fails closed. A pin digest
mismatch fails closed. The helpers do not write `RUNNER_TOKEN` to disk.
