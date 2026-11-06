#!/usr/bin/env bash
# Build the isolated toolchain image; no host packages or sudo required.
set -euo pipefail
cd "$(dirname "$0")/.."
docker build --platform linux/amd64 -t pongo-lab-toolchain:bullseye toolchain
