#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/flatpak/com.rnd.bambu_lan.yml"
BUILD_DIR="$ROOT_DIR/build/flatpak"
REPO_DIR="$ROOT_DIR/build/flatpak-repo"
BUNDLE_PATH="$ROOT_DIR/build/com.rnd.bambu_lan.flatpak"

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

# Bundle libmpv into app lib dir so Flatpak runtime can resolve it.
BUNDLE_LIB_DIR="$ROOT_DIR/build/linux/x64/release/bundle/lib"
mkdir -p "$BUNDLE_LIB_DIR"
LIBMPV_PATH="$(ldconfig -p | awk '/libmpv\\.so\\.2/{print $NF; exit}')"
if [[ -z "${LIBMPV_PATH:-}" ]]; then
  LIBMPV_PATH="$(find /usr/lib64 /lib64 /usr/lib /lib -maxdepth 3 -type f -name 'libmpv.so.2*' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${LIBMPV_PATH:-}" || ! -f "$LIBMPV_PATH" ]]; then
  echo "libmpv.so.2 not found on host. Install libmpv first (e.g. dnf install mpv-libs)." >&2
  exit 1
fi
cp -Lf "$LIBMPV_PATH" "$BUNDLE_LIB_DIR/libmpv.so.2"

# Recursively vendor transitive shared library dependencies for libmpv.
# This avoids iterative Flatpak runtime failures (missing libass, libpulsecommon, etc).
declare -A seen

is_core_runtime_lib() {
  local base
  base="$(basename "$1")"
  case "$base" in
    ld-linux-*.so*|linux-vdso.so*|libc.so*|libm.so*|libpthread.so*|librt.so*|libdl.so*|libgcc_s.so*|libstdc++.so*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_direct_deps() {
  local target="$1"
  ldd "$target" 2>/dev/null | awk '
    /=> \// { print $3 }
    /^\// { print $1 }
  ' | sort -u
}

vendor_dep_tree() {
  local root="$1"
  local dep
  while IFS= read -r dep; do
    [[ -z "$dep" || ! -f "$dep" ]] && continue
    is_core_runtime_lib "$dep" && continue
    if [[ -n "${seen[$dep]:-}" ]]; then
      continue
    fi
    seen["$dep"]=1
    cp -Lf "$dep" "$BUNDLE_LIB_DIR/$(basename "$dep")"
    vendor_dep_tree "$dep"
  done < <(collect_direct_deps "$root")
}

vendor_dep_tree "$LIBMPV_PATH"
echo "Vendored ${#seen[@]} shared libs for libmpv dependency closure."

# Build flatpak.
flatpak-builder --force-clean "$BUILD_DIR" "$MANIFEST"

# Create a repo and bundle for easy install/share.
flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_PATH" com.rnd.bambu_lan

echo "Flatpak bundle created: $BUNDLE_PATH"
