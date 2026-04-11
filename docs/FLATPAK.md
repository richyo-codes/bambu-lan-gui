# Flatpak Build & Run

## App ID

- `com.rnd.boomprint`

## Current packaging model

The Flatpak manifest builds `mpv` (with `libmpv`) **inside Flatpak** as a module.

This is based on the approach used by `flathub/io.mpv.Mpv` and avoids host ABI/glibc mismatch.

Key points:

- No host library fallback (`/run/host/...`) for app runtime.
- No host `libmpv` copy.
- Launcher uses only app/runtime library locations:
  - `LD_LIBRARY_PATH=/app/lib:/app/bin/lib`

## Build in container (recommended)

```bash
cd /home/ry/code_flutter/rnd_bambu_rtsp
flutter build linux --release
./tool/build_flatpak_container.sh
```

To keep Flatpak builder artifacts out of the repo tree:

```bash
./tool/build_flatpak_container.sh --tmp
./tool/build_flatpak_container.sh --out-dir /tmp/my-flatpak-build
```

This script:

1. Uses Podman/Docker with `ghcr.io/flathub-infra/flatpak-builder-lint:latest`
2. Installs Flatpak runtime + SDK `24.08`
3. Builds modules from `flatpak/com.rnd.boomprint.yml`
4. Writes bundle to `build/com.rnd.boomprint.flatpak`

## Install & run

```bash
flatpak install --user --reinstall ./build/com.rnd.boomprint.flatpak
flatpak run com.rnd.boomprint
```

If you used `--tmp` or `--out-dir`, install from that bundle path instead:

```bash
flatpak install --user --reinstall /tmp/rnd_bambu_rtsp-flatpak/com.rnd.boomprint.flatpak
```

## Troubleshooting

Check what the app sees:

```bash
flatpak run --command=sh com.rnd.boomprint -c 'echo "$LD_LIBRARY_PATH"; ldd /app/bin/boomprint | grep "not found" || true'
```

If module build fails, inspect builder output for the failing module (`mpv` or one of its deps), then adjust module config in:

- `flatpak/com.rnd.boomprint.yml`

## Key files

- Manifest: `flatpak/com.rnd.boomprint.yml`
- Container build script: `tool/build_flatpak_container.sh`
- Local host build script: `tool/build_flatpak.sh`
