#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# Ensure linux/ matches linux_gtk4 before launching with the GTK4 local engine.
"$ROOT_DIR/tool/use_gtk4_runner.sh"

rm -rf "$ROOT_DIR/build/linux"

FLUTTER_BIN="${FLUTTER_BIN:-/mnt/ssd-dev/git/flutter-gtk4/bin/flutter}"
LOCAL_ENGINE_SRC="${LOCAL_ENGINE_SRC:-/mnt/ssd-dev/git/flutter-gtk4/engine/src}"
#LOCAL_ENGINE_SRC="${LOCAL_ENGINE_SRC:-/mnt/ssd-dev/git/flutter_feature/engine/src}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter binary not found or not executable: $FLUTTER_BIN" >&2
  exit 1
fi

# "$FLUTTER_BIN" run -d linux -v \
#   --verbose-system-logs \
#   --local-engine=host_debug_unopt \
#   --local-engine-host=host_debug_unopt \
#   --local-engine-src-path="$LOCAL_ENGINE_SRC" \
#   "$@"

export MEDIA_KIT_GTK4_DEBUG=1

"$FLUTTER_BIN" run -d linux -v \
   --local-engine=host_debug_unopt \
   --local-engine-host=host_debug_unopt \
  --local-engine-src-path="$LOCAL_ENGINE_SRC" \
  "$@"
