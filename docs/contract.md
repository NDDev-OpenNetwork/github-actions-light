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

## Failure

A missing, expired, or replayed registration token fails closed. A pin digest
mismatch fails closed. The helpers do not write `RUNNER_TOKEN` to disk.
