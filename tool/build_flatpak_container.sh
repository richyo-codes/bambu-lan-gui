#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/flatpak/com.rnd.bambu_lan.yml"
BUILD_DIR="$ROOT_DIR/build/flatpak"
REPO_DIR="$ROOT_DIR/build/flatpak-repo"
BUNDLE_PATH="$ROOT_DIR/build/com.rnd.bambu_lan.flatpak"
APP_ID="com.rnd.bambu_lan"
CONTAINER_ROOT="/src"
CONTAINER_MANIFEST="$CONTAINER_ROOT/flatpak/com.rnd.bambu_lan.yml"
CONTAINER_BUILD_DIR="$CONTAINER_ROOT/build/flatpak"
CONTAINER_REPO_DIR="$CONTAINER_ROOT/build/flatpak-repo"
CONTAINER_BUNDLE_PATH="$CONTAINER_ROOT/build/com.rnd.bambu_lan.flatpak"

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

mkdir -p "$ROOT_DIR/build"

# Ensure Flutter release bundle exists.
HOST_BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
if [[ ! -f "$HOST_BUNDLE_DIR/printer_lan" ]]; then
  echo "Missing $HOST_BUNDLE_DIR/printer_lan. Run: flutter build linux --release" >&2
  exit 1
fi

# Use SELinux-safe mount label for Podman. Docker ignores ':Z'.
MOUNT_SPEC="$ROOT_DIR:/src:Z"

"$ENGINE" run --rm -it \
  --privileged \
  --device /dev/fuse \
  --security-opt label=disable \
  --entrypoint /bin/bash \
  -v "$MOUNT_SPEC" \
  -w /src \
  "$IMAGE" \
  -lc "
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

echo "Flatpak bundle created: $BUNDLE_PATH"
echo "Install with: flatpak install --user --reinstall $BUNDLE_PATH"
