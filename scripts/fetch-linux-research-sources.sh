#!/usr/bin/env bash
# Fetch pinned Hoolock m1n1, kernel, and documented configuration sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="${LINUX_RESEARCH_SOURCE_DIR:-$ROOT/build/sources}"

fetch_repo() {
  local url=$1 dest=$2 commit=$3 branch=${4:-}
  local -a clone_args=(--filter=blob:none --no-checkout --recursive)
  if [[ -n "$branch" ]]; then
    clone_args+=(--depth 1 --branch "$branch" --single-branch)
  fi
  if [[ ! -d "$dest/.git" ]]; then
    git clone "${clone_args[@]}" "$url" "$dest"
  fi
  if ! git -C "$dest" rev-parse -q --verify "$commit^{commit}" >/dev/null; then
    git -C "$dest" fetch origin "$commit" || git -C "$dest" fetch origin
  fi
  git -C "$dest" checkout --detach "$commit"
  git -C "$dest" submodule update --init --checkout --recursive
  [[ "$(git -C "$dest" rev-parse HEAD)" == "$commit" ]] || {
    echo "Source commit mismatch at $dest" >&2
    exit 1
  }
}

fetch_repo https://github.com/HoolockLinux/m1n1.git \
  "$SOURCES/m1n1-idevice" d5a10ac52a6468484854419a6c5130f1d62073eb

fetch_repo https://github.com/HoolockLinux/linux.git \
  "$SOURCES/hoolock-linux" 6831bc701a6ce059e71e5aaa9488c9195bea6927 hoolock

fetch_repo https://github.com/HoolockLinux/docs.git \
  "$SOURCES/hoolock-docs" 23ebe1fbc375599221553a7e1815e5de182a6b42

expected_config=a5cbcb0d3fe655888106672e6fe03477b63d51bd36bbcfc4f5145627d906b208
actual_config=$(sha256sum "$SOURCES/hoolock-docs/config_16k" | awk '{print $1}')
[[ "$actual_config" == "$expected_config" ]] || {
  echo "Hoolock config hash mismatch" >&2
  exit 1
}

cat <<EOF
Sources fetched:
  m1n1:  d5a10ac52a6468484854419a6c5130f1d62073eb
  linux: 6831bc701a6ce059e71e5aaa9488c9195bea6927
  docs:  23ebe1fbc375599221553a7e1815e5de182a6b42
  config SHA-256: $actual_config
EOF
