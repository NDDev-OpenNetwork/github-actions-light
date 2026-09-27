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

Jobs inherit the runner process environment plus `${PIN_ROOT}/<instance>/.env`,
which the installer seeds with `LANG=C.UTF-8` and a `PATH` that adds the
slot-local `.local/bin` and `/usr/local/cargo/bin` ahead of the system
defaults. Slots provisioned before this contract need the same `.env` entries
written by hand; a running slot must be restarted once to pick them up.

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

## Failure

A missing, expired, or replayed registration token fails closed. A pin digest
mismatch fails closed. The helpers do not write `RUNNER_TOKEN` to disk.
