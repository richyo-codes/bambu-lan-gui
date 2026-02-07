#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/flatpak/com.example.RndBambuRtspStream.yml"
BUILD_DIR="$ROOT_DIR/build/flatpak"
REPO_DIR="$ROOT_DIR/build/flatpak-repo"
BUNDLE_PATH="$ROOT_DIR/build/com.example.RndBambuRtspStream.flatpak"

if ! command -v flatpak-builder >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    echo "flatpak-builder not found. Install: sudo dnf install -y flatpak flatpak-builder" >&2
  else
    echo "flatpak-builder not found. Install: sudo apt-get install flatpak flatpak-builder" >&2
  fi
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH." >&2
  exit 1
fi

# Build Flutter Linux bundle first (manifest expects build/linux/x64/release/bundle).
flutter build linux --release

# Build flatpak.
flatpak-builder --force-clean "$BUILD_DIR" "$MANIFEST"

# Create a repo and bundle for easy install/share.
flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_PATH" com.example.RndBambuRtspStream

echo "Flatpak bundle created: $BUNDLE_PATH"
