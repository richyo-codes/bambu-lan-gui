#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/flatpak/com.rnd.bambu_lan.yml"
APP_ID="com.rnd.bambu_lan"
CONTAINER_ROOT="/src"
CONTAINER_MANIFEST="$CONTAINER_ROOT/flatpak/com.rnd.bambu_lan.yml"
DEFAULT_OUT_DIR="$ROOT_DIR/build"
TMP_OUT_DIR="/tmp/rnd_bambu_rtsp-flatpak"

usage() {
  cat <<'EOF'
Usage: ./tool/build_flatpak_container.sh [--tmp] [--out-dir PATH]

  --tmp           Store Flatpak builder artifacts under /tmp.
  --out-dir PATH  Store Flatpak builder artifacts under PATH.
EOF
}

OUT_DIR="$DEFAULT_OUT_DIR"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmp)
      OUT_DIR="$TMP_OUT_DIR"
      shift
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "--out-dir requires a path." >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
BUILD_DIR="$OUT_DIR/flatpak"
REPO_DIR="$OUT_DIR/flatpak-repo"
BUNDLE_PATH="$OUT_DIR/com.rnd.bambu_lan.flatpak"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Flatpak manifest not found: $MANIFEST" >&2
  exit 1
fi

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "Neither podman nor docker was found in PATH." >&2
  exit 1
fi

IMAGE="ghcr.io/flathub-infra/flatpak-builder-lint:latest"

# Ensure Flutter release bundle exists.
HOST_BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
if [[ ! -f "$HOST_BUNDLE_DIR/printer_lan" ]]; then
  echo "Missing $HOST_BUNDLE_DIR/printer_lan. Run: flutter build linux --release" >&2
  exit 1
fi

# Use SELinux-safe mount label for Podman. Docker ignores ':Z'.
MOUNT_SPEC="$ROOT_DIR:/src:Z"
OUT_MOUNT_SPEC=
CONTAINER_OUT_ROOT="$CONTAINER_ROOT/build"

if [[ "$OUT_DIR" == "$DEFAULT_OUT_DIR" ]]; then
  CONTAINER_BUILD_DIR="$CONTAINER_ROOT/build/flatpak"
  CONTAINER_REPO_DIR="$CONTAINER_ROOT/build/flatpak-repo"
  CONTAINER_BUNDLE_PATH="$CONTAINER_ROOT/build/com.rnd.bambu_lan.flatpak"
else
  OUT_MOUNT_SPEC="-v $OUT_DIR:/out:Z"
  CONTAINER_OUT_ROOT="/out"
  CONTAINER_BUILD_DIR="$CONTAINER_OUT_ROOT/flatpak"
  CONTAINER_REPO_DIR="$CONTAINER_OUT_ROOT/flatpak-repo"
  CONTAINER_BUNDLE_PATH="$CONTAINER_OUT_ROOT/com.rnd.bambu_lan.flatpak"
fi

TTY_ARGS=()
if [[ -t 0 && -t 1 ]]; then
  TTY_ARGS=(-it)
fi

CONTAINER_COMMAND="
  set -euo pipefail
  flatpak-builder --version
  dbus-uuidgen --ensure=/etc/machine-id
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak remotes || true
  # Preinstall only required runtime/SDK and avoid related refs (e.g. openh264),
  # which can fail in restricted container bwrap environments.
  flatpak --system install -y --noninteractive --no-related flathub \
    org.freedesktop.Sdk/x86_64/25.08 \
    org.freedesktop.Platform/x86_64/25.08

  flatpak-builder --disable-rofiles-fuse --force-clean '$CONTAINER_BUILD_DIR' '$CONTAINER_MANIFEST'
  flatpak-builder --disable-rofiles-fuse --force-clean --repo='$CONTAINER_REPO_DIR' '$CONTAINER_BUILD_DIR' '$CONTAINER_MANIFEST'
  flatpak build-bundle '$CONTAINER_REPO_DIR' '$CONTAINER_BUNDLE_PATH' '$APP_ID'
"

# In CI with Docker, the workspace is often itself inside another container.
# Bind-mounting that path into a sibling Docker container fails because the host
# daemon cannot see the inner-container filesystem. Copy the repo into the build
# container instead, then copy the resulting Flatpak bundle back out.
USE_COPY_MODE=0
if [[ "$ENGINE" == "docker" ]] && [[ -n "${CI:-}${GITHUB_ACTIONS:-}${GITEA_ACTIONS:-}${ACT:-}" ]]; then
  USE_COPY_MODE=1
fi

if [[ "$USE_COPY_MODE" == "1" ]]; then
  CONTAINER_BUILD_DIR="$CONTAINER_ROOT/build/flatpak"
  CONTAINER_REPO_DIR="$CONTAINER_ROOT/build/flatpak-repo"
  CONTAINER_BUNDLE_PATH="$CONTAINER_ROOT/build/com.rnd.bambu_lan.flatpak"

  CONTAINER_ID=$(
    "$ENGINE" create \
      --privileged \
      --device /dev/fuse \
      --security-opt label=disable \
      --entrypoint /bin/bash \
      -w "$CONTAINER_ROOT" \
      "$IMAGE" \
      -lc "$CONTAINER_COMMAND"
  )

  cleanup() {
    "$ENGINE" rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  "$ENGINE" cp "$ROOT_DIR/." "$CONTAINER_ID:$CONTAINER_ROOT"
  "$ENGINE" start -a "$CONTAINER_ID"
  "$ENGINE" cp "$CONTAINER_ID:$CONTAINER_BUNDLE_PATH" "$OUT_DIR/"
else
  "$ENGINE" run --rm "${TTY_ARGS[@]}" \
    --privileged \
    --device /dev/fuse \
    --security-opt label=disable \
    --entrypoint /bin/bash \
    -v "$MOUNT_SPEC" \
    ${OUT_MOUNT_SPEC:+-v "$OUT_DIR:/out:Z"} \
    -w /src \
    "$IMAGE" \
    -lc "$CONTAINER_COMMAND"
fi

echo "Flatpak bundle created: $BUNDLE_PATH"
echo "Install with: flatpak install --user --reinstall $BUNDLE_PATH"
