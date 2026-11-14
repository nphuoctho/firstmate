#!/usr/bin/env bash
# Launch the primary Pi session with the primary-only packages. Workers never get these.
# Usage: ai-native/pi-primary.sh [pi args...]    LENS=1 also loads pi-lens (~0.6-1.2 GB).
set -euo pipefail
args=(-e npm:pi-open-tui)
[ "${LENS:-0}" = 1 ] && args+=(-e npm:pi-lens)
exec pi "${args[@]}" "$@"
