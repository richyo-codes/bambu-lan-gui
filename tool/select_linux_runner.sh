#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VARIANT="${1:-gtk3}"

case "$VARIANT" in
  gtk3)
    # CI checkouts already default to the tracked GTK3-compatible linux/ runner.
    # If a local linux_gtk3 template exists, prefer it to restore the workspace.
    if [[ -d "$ROOT_DIR/linux_gtk3" ]]; then
      "$ROOT_DIR/tool/use_gtk3_runner.sh"
    else
      echo "Using default GTK3 linux runner from repository checkout."
    fi
    ;;
  gtk4)
    "$ROOT_DIR/tool/use_gtk4_runner.sh"
    ;;
  *)
    echo "Unsupported Linux runner variant: $VARIANT" >&2
    echo "Expected one of: gtk3, gtk4" >&2
    exit 1
    ;;
esac
