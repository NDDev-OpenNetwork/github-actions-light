# GitHub Actions light

Install and run the official GitHub [Actions runner](https://github.com/actions/runner)
on a Linux host. This repository is the public install contract: a pinned
runner tarball, systemd units, and registration helpers.

It is not a scheduler. GitHub remains the workflow queue, permission model,
and check status. There is no admission controller, placement engine, warm
pool, or custom job queue here.

## What this product does

- Download one checksum-pinned `actions/runner` release
- Install one systemd instance per concurrent job slot
- Register that instance against an organization or a repository
- Apply a single extra label: `nddev-linux`

GitHub already stamps `self-hosted`, `Linux`, and `X64`. Callers of private
workflows pass `nddev-linux` (or `[self-hosted, nddev-linux]`). Public
repositories must keep using GitHub-hosted labels such as `ubuntu-latest`.

## What this product does not do

- Schedule or preempt GitHub jobs
- Share one runner process across unrelated GitHub organizations
- Provision Incus, GARM, Kubernetes, or a custom cache broker
- Place production deploy credentials on the runner host
- Run public or fork pull-request code on private hardware

Organization runners serve that organization only. Personal repositories
need repository registrations. There is no GitHub Enterprise pool in this
contract.

## Install

Root on Ubuntu 24.04:

```bash
sudo scripts/install-runner.sh \
  --instance org-a-1 \
  --url https://github.com/example-org \
  --name example-org-linux-1
```

`RUNNER_TOKEN` must be in the environment. Create it with the GitHub API
registration-token endpoint for the target organization or repository. The
token is single-use and short-lived; the script never writes it to disk.

Add `--docker` only when this slot must run Docker/service-container jobs.
That grants the runner user access to the host Docker socket. Do not combine
untrusted workflows with `--docker`.

Unregister:

```bash
sudo scripts/unregister-runner.sh --instance org-a-1
```

`RUNNER_TOKEN` is again required so `config.sh remove` can delete the GitHub
registration.

## Layout

| Path | Role |
|---|---|
| `config/runner-pin.json` | Exact runner version, URL, SHA-256 |
| `systemd/gha-runner@.service` | Hardened slot without Docker |
| `systemd/gha-runner-docker@.service` | Slot with host Docker |
| `scripts/install-runner.sh` | Download, verify, configure, enable |
| `scripts/unregister-runner.sh` | Stop, remove GitHub registration |
| `examples/host.yaml` | Synthetic host inventory (documentation only) |

Real host addresses, organization names, and credentials belong in a private
estate overlay, not in this repository.

## Verification

```bash
scripts/validate_module.sh
```

Public CI for this repository runs on `ubuntu-latest` only.
