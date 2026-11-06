#!/usr/bin/env bash
# No-hardware checks for portable Juan applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/test-linux-apps.sh"
python3 -m py_compile "$ROOT/simulator/fake_device.py" "$ROOT/simulator/run-hello.py"
python3 "$ROOT/simulator/run-hello.py" --build-dir "$ROOT/build/linux-apps"
python3 - "$ROOT/linux-apps/apps.list" <<'PY'
from pathlib import Path
import sys

lines = [
    line.split()
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if line and not line.startswith("#")
]
assert lines and [line[0] for line in lines] == ["hello-juan"], lines
print("linux-apps package list checks passed")
PY
