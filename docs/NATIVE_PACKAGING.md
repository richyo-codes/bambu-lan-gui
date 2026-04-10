# Native Linux Packaging

This project can produce distro-native packages that rely on system libraries
instead of vendoring `libmpv` and related desktop stack dependencies.

Current target families:

- Ubuntu 24.04 and newer via `.deb`
- Fedora 43 and newer via `.rpm`

These packages install the Flutter Linux release bundle under:

```text
/opt/bambu-buddy
```

and expose a launcher command:

```text
/usr/bin/bambu-buddy
```

## Why this approach

Compared with Flatpak/AppImage, native packages:

- rely on the distro's own `mpv`, GTK, PulseAudio/ALSA, and OpenSSL packages
- are smaller
- integrate better with the target distro
- avoid vendoring desktop multimedia libraries

The tradeoff is that dependency names are distro-specific, so `.deb` and `.rpm`
must be built separately.

## Package Contents

Shared packaging assets live under:

```text
packaging/common/
packaging/rpm/
```

Build scripts:

```text
tool/build_deb.sh
tool/build_rpm.sh
```

Both scripts expect an existing Flutter Linux release bundle at:

```text
build/linux/x64/release/bundle
```

Build it first:

```bash
flutter build linux --release
```

## Build a Debian package

Ubuntu 24.04 or newer:

```bash
sudo apt-get update
sudo apt-get install -y dpkg-dev
bash ./tool/build_deb.sh
```

Output:

```text
build/packages/deb/bambu-buddy_<version>_<arch>.deb
```

Default runtime dependencies declared by the package:

- `libgtk-3-0`
- `libmpv2`
- `libpulse0`
- `libasound2 | libasound2t64`
- `libssl3`
- `libstdc++6`
- `zlib1g`

## Build an RPM package

Fedora 43 or newer:

```bash
sudo dnf install -y rpm-build
bash ./tool/build_rpm.sh
```

Output:

```text
build/packages/rpm/
```

Default runtime dependencies declared by the spec:

- `gtk3`
- `mpv-libs`
- `pulseaudio-libs`
- `alsa-lib`
- `openssl-libs`
- `libstdc++`
- `zlib`

## Versioning

By default, both scripts read the version from `pubspec.yaml`.

Examples:

```bash
bash ./tool/build_deb.sh --version 1.2.3+4
bash ./tool/build_rpm.sh --version 1.2.3+4
bash ./tool/build_deb.sh --version v1.2.3-17-gabc1234
bash ./tool/build_rpm.sh --version v1.2.3-17-gabc1234
```

RPM uses:

- `Version: 1.2.3`
- `Release: 4`

If no `+build` suffix exists, RPM defaults to `Release: 1`.

Both scripts also normalize raw `git describe` output from CI:

- Debian: `v1.2.3-17-gabc1234` -> `1.2.3+17.gabc1234`
- RPM: `v1.2.3-17-gabc1234` -> `Version: 1.2.3`, `Release: 17.gabc1234`

## Verify runtime dependencies

Before finalizing the package metadata, inspect the Linux bundle against the
target distro:

```bash
ldd build/linux/x64/release/bundle/printer_lan
find build/linux/x64/release/bundle/lib -maxdepth 1 -type f -name '*.so' -exec ldd {} \\;
```

This is the fastest way to confirm whether the declared package dependencies
still match the current bundle.

## Recommended build strategy

Build each package on the oldest distro you plan to support:

- build `.deb` on Ubuntu 24.04
- build `.rpm` on Fedora 43

That gives the best chance that newer releases in the same family will run the
package without ABI issues.
