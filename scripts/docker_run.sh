#!/usr/bin/env bash
# Run a command inside the HDL tool container with the repo mounted at /work.
#   scripts/docker_run.sh make test
#   scripts/docker_run.sh python3 scripts/run_tests.py --only tb_uart
set -euo pipefail
IMAGE="${HDL_IMAGE:-devtools:latest}"
cd "$(dirname "$0")/.."
exec docker run --rm --init --user "$(id -u):$(id -g)" -v "$PWD":/work -w /work "$IMAGE" "$@"
