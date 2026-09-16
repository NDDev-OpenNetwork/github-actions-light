# Contributing

This repository is an install contract for the official GitHub Actions runner.
It is not a job scheduler.

Please report security problems privately per [SECURITY.md](SECURITY.md).

## Rules

- Public CI stays on `ubuntu-latest`. No self-hosted label in this repository.
- Do not add GARM, Incus, admission, placement, or a custom queue.
- Do not embed real host, organization, or credential values.
- Pin `actions/runner` by version, URL, and SHA-256 in `config/runner-pin.json`.
- Pin third-party GitHub Actions by full SHA in `catalog/actions.yml`.

## Before a pull request

```
bash scripts/validate_module.sh
```
