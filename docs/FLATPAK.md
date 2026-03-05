# Flatpak Build & Run

## App ID

- `com.rnd.bambu_lan`

## Build a Flatpak bundle

```bash
cd /home/ry/code_flutter/rnd_bambu_rtsp
./tool/build_flatpak.sh
```

This script:

1. Runs `flutter build linux --release`
2. Builds Flatpak from `flatpak/com.rnd.bambu_lan.yml`
3. Writes bundle to `build/com.rnd.bambu_lan.flatpak`

## Install & run locally

```bash
flatpak install --user --reinstall ./build/com.rnd.bambu_lan.flatpak
flatpak run com.rnd.bambu_lan
```

## Runtime media libraries

`ffmpeg-full` does **not** provide `libmpv.so.2`; it provides FFmpeg codec libs.

This project now vendors `libmpv.so.2` into the app bundle during `./tool/build_flatpak.sh`:

- `libmpv.so.2` resolved via `ldconfig -p` (with fallback path scan)
- copied to `build/linux/x64/release/bundle/lib/libmpv.so.2`

So at runtime:

- host runtime libs are searched first (`/run/host/usr/lib64:/run/host/lib64`)
- app bundle libs are searched after (`/app/bin/lib:/app/lib`)
- `libmpv.so.2` is available from app bundle
- codec stack can leverage `org.freedesktop.Platform.ffmpeg-full`

Current manifest also includes a host-library fallback for Fedora-like setups:

- `--filesystem=host-os:ro`
- `LD_LIBRARY_PATH` includes `/run/host/usr/lib64` and `/run/host/lib64`

This improves local compatibility when host `mpv-libs` has extra deps not present in runtime.
Tradeoff: less portable/reproducible than building against Flatpak SDK/runtime libraries only.

## Why `libmpv.so.2` can still be missing

The app relies on `libmpv` from the Flatpak runtime extension:

- `org.freedesktop.Platform.ffmpeg-full//24.08`

Flatpak always installs hard runtime dependencies (`runtime`, `sdk`), but extension behavior can vary for local bundle installs. In practice, local installs may need manual extension install.

If you get:

- `error while loading shared libraries: libmpv.so.2: cannot open shared object file`

install extension explicitly:

```bash
flatpak install --user flathub org.freedesktop.Platform.ffmpeg-full//24.08
```

Then run again:

```bash
flatpak run com.rnd.bambu_lan
```

If build script fails with missing host `libmpv.so.2`, install host package first:

- Fedora: `sudo dnf install -y mpv-libs`

## Debug commands

Check runtime library path seen by app sandbox:

```bash
flatpak run --command=sh com.rnd.bambu_lan -c 'echo "$LD_LIBRARY_PATH"'
```

Find `libmpv` inside sandbox-visible extension paths:

```bash
flatpak run --command=sh com.rnd.bambu_lan -c 'find /usr/lib/extensions -name "libmpv.so*" 2>/dev/null'
```

## Key files

- Manifest: `flatpak/com.rnd.bambu_lan.yml`
- Build script: `tool/build_flatpak.sh`
