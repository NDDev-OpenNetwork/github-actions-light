#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

python3 -m py_compile scripts/light_contract.py tests/test_light_contract.py
python3 -m unittest discover -s tests -v
python3 scripts/light_contract.py
