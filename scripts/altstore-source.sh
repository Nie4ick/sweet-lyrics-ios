#!/usr/bin/env bash
# Compatibility entry point: stable by default, or pass testing as the second argument.
set -euo pipefail
python3 "$(dirname "$0")/altstore-source.py" "${1:-altstore-source.json}" --channel "${2:-stable}"
