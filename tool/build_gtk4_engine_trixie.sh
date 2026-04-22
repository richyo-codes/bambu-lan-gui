#!/usr/bin/env bash
set -euo pipefail

ENGINE_ROOT="${ENGINE_ROOT:-/mnt/ssd-dev/git/flutter-gtk4/engine/src}"
TOOLS_GN="$ENGINE_ROOT/flutter/tools/gn"
OUT_DIR_NAME="${OUT_DIR_NAME:-host_debug_unopt_trixie}"
OUT_DIR="$ENGINE_ROOT/out/$OUT_DIR_NAME"
TRIXIE_SYSROOT="${TRIXIE_SYSROOT:-}"

if [[ -z "$TRIXIE_SYSROOT" ]]; then
  echo "TRIXIE_SYSROOT is required." >&2
  echo "Example:" >&2
  echo "  TRIXIE_SYSROOT=/path/to/debian_trixie_amd64-sysroot tool/build_gtk4_engine_trixie.sh" >&2
  exit 1
fi

if [[ ! -x "$TOOLS_GN" ]]; then
  echo "GN helper not found: $TOOLS_GN" >&2
  exit 1
fi

if [[ ! -d "$TRIXIE_SYSROOT" ]]; then
  echo "Trixie sysroot directory not found: $TRIXIE_SYSROOT" >&2
  exit 1
fi

echo "Generating engine build in: $OUT_DIR"
"$TOOLS_GN" \
  --linux \
  --unoptimized \
  --runtime-mode debug \
  --target-dir "$OUT_DIR_NAME" \
  --target-sysroot "$TRIXIE_SYSROOT" \
  --no-default-linux-sysroot \
  --enable-vulkan \
  --gn-args='use_gtk4=true use_gtk4_native_compositor=true'

echo "Building flutter_linux_gtk in: $OUT_DIR"
autoninja -C "$OUT_DIR" flutter_linux_gtk

cat <<EOF

Build completed.

Run the app against this engine with:
  LOCAL_ENGINE=$OUT_DIR_NAME tool/gtk4_build.sh
EOF
