#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "script/build_and_run.sh is kept for compatibility; use script/package_app.sh for packaging or script/run_app.sh for local runs." >&2
exec "$ROOT_DIR/script/package_app.sh" "$@"
