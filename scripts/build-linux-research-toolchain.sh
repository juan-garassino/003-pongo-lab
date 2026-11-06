#!/usr/bin/env bash
# Build the isolated m1n1/Linux research toolchain image. No USB passthrough.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker build --platform linux/amd64 \
  -t pongo-lab-linux-research:trixie \
  -f "$ROOT/toolchain/linux-research.Dockerfile" "$ROOT/toolchain"
