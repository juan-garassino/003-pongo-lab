#!/usr/bin/env bash
# Vendor m1n1's Rust dependencies, then build with Docker networking disabled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="${LINUX_RESEARCH_SOURCE_DIR:-$ROOT/build/sources}"
RUST="$SOURCES/m1n1-idevice/rust"
[[ -f "$RUST/Cargo.lock" ]] || {
  echo "Missing m1n1 Rust source: $RUST" >&2
  exit 1
}

cd "$RUST"
cargo vendor --locked vendor
mkdir -p .cargo
cat > .cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source."git+https://github.com/rafalh/rust-fatfs?rev=4eccb50d011146fbed20e133d33b22f3c27292e7"]
git = "https://github.com/rafalh/rust-fatfs"
rev = "4eccb50d011146fbed20e133d33b22f3c27292e7"
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF
