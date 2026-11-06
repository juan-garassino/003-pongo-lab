#!/usr/bin/env bash
# Laptop-only build. No USB devices are passed into the container.
set -euo pipefail
cd "$(dirname "$0")/.."

docker build --platform linux/amd64 -t pongo-lab-toolchain:bullseye toolchain
docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --network none \
  --mount "type=bind,source=$PWD,target=/work" \
  pongo-lab-toolchain:bullseye
