#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LINUX_DIR="$ROOT_DIR/linux"
GTK3_DIR="$ROOT_DIR/linux_gtk3"
GTK4_BACKUP_DIR="$ROOT_DIR/linux_gtk4"

if [[ ! -d "$GTK3_DIR" ]]; then
  echo "Missing GTK3 runner template: $GTK3_DIR" >&2
  exit 1
fi

if [[ -L "$LINUX_DIR" ]]; then
  rm "$LINUX_DIR"
elif [[ -d "$LINUX_DIR" ]]; then
  if [[ ! -d "$GTK4_BACKUP_DIR" ]]; then
    cp -a "$LINUX_DIR" "$GTK4_BACKUP_DIR"
    echo "Backed up current linux runner to: linux_gtk4"
  fi
  rm -rf "$LINUX_DIR"
fi

cp -a "$GTK3_DIR" "$LINUX_DIR"

echo "Switched runner: linux_gtk3 -> linux"
echo "Build with: flutter run -d linux"
