# Protocol Package Extraction Plan

Goal: extract a pure Dart protocol/client package first, without dragging app state, settings, media playback, or Flutter UI into it.

## Target Boundary

Move into package:
- MQTT client and command publishing
- FTP/FTPS client and file operations
- printer/domain models
- report parsing and ACK parsing
- protocol enums and command helpers
- generic LAN config objects
- generic 3MF parsing only if it stays UI-agnostic

Keep in app:
- `ConnectionController`
- `SettingsManager`
- `SensitiveAuth`
- `MonitoringAlerts`
- `media_kit` playback and reconnect logic
- feature flags
- all widgets and pages

## Proposed Package Layout

Create:
- `packages/boomprint_connectivity/`
  - `lib/boomprint_connectivity.dart`
  - `lib/src/models/...`
  - `lib/src/mqtt/...`
  - `lib/src/ftp/...`
  - `lib/src/client/...`
  - `test/...`

Suggested public API:
- `BambuLanConfig`
- `BambuPrintStatus`
- `BambuReportEvent`
- `BambuCommandEvent`
- `BambuSpeedProfile`
- `BambuMqtt`
- `BambuFtp`
- `BambuLan`

## Phase 1: Prepare the Boundary In-Repo

Before creating the package, clean up the current code so extraction is mechanical.

1. Make protocol files Flutter-free.
   - Verify `bambu_mqtt.dart`, `bambu_ftp.dart`, `bambu_lan.dart` do not import Flutter.
   - Remove any app/UI-specific assumptions from those files.
   - Prefer `dart:io`, `dart:async`, and package-local model imports only.

2. Move generic helpers down into protocol layer.
   - ACK parsing helpers currently living in app-specific places should move next to MQTT client code.
   - Any print command envelope parsing should live with MQTT protocol code, not pages.

3. Identify app-owned wrappers.
   - `connection_controller.dart` should depend on protocol package types, not the other way around.
   - It remains the adapter between app behavior and protocol operations.

## Phase 2: Create the Package Skeleton

1. Create `packages/boomprint_connectivity/pubspec.yaml`
   - pure Dart package
   - dependencies only for protocol/client work
   - no `flutter:` SDK dependency

2. Add library barrel:
   - `lib/boomprint_connectivity.dart`

3. Add initial folders:
   - `lib/src/models/`
   - `lib/src/mqtt/`
   - `lib/src/ftp/`
   - `lib/src/client/`

## Phase 3: Move the Core Types

Move first:
- `BambuLanConfig`
- `FtpEntry`
- `BambuReportEvent`
- `BambuPrintStatus`
- `BambuCommandEvent`
- `BambuSpeedProfile`

Reason:
- these are the lowest-risk shared primitives
- once stable, both the app and the package internals can depend on them cleanly

Likely files:
- `src/models/config.dart`
- `src/models/print_status.dart`
- `src/models/events.dart`
- `src/models/speed_profile.dart`

## Phase 4: Move Protocol Implementations

Move next:
- `bambu_mqtt.dart`
- `bambu_ftp.dart`
- `bambu_lan.dart`

While moving:
- keep public API small
- hide parsing/internal helpers under `src/`
- export only intended entry points from the package barrel

## Phase 5: Rewire the App

In app `pubspec.yaml`:
- add path dependency to `packages/boomprint_connectivity`

Then update imports:
- replace local imports of `bambu_lan.dart`, `bambu_mqtt.dart`, `bambu_ftp.dart`
- import from `package:boomprint_connectivity/...`

Do not move yet:
- `connection_controller.dart`
- settings persistence
- playback logic

That keeps the app behavior stable while the protocol layer becomes reusable.

## Phase 6: Add Package Tests

Add package-level tests before deeper refactors.

Highest-value tests:
- MQTT ACK parsing
- speed-profile fallback behavior
- sequence/ACK matching
- report parsing into `BambuPrintStatus`
- path normalization for printer file paths
- FTP print path/url generation
- 3MF-independent command payload generation

Good initial test names:
- `test/mqtt_ack_test.dart`
- `test/mqtt_speed_profile_test.dart`
- `test/print_status_parse_test.dart`
- `test/ftp_path_normalization_test.dart`

## Phase 7: Tighten the Public API

After app is using the package:
- reduce exported surface
- keep internal helpers under `src/`
- document the intended reusable API
- avoid exposing app-specific naming or assumptions

## Non-Goals for First Extraction

Do not do these in the first pass:
- multi-vendor abstraction
- generic printer framework
- moving `ConnectionController`
- moving settings storage
- moving playback/reconnect logic
- moving notifications/auth

Those belong to later phases.

## Risks To Watch

- app pages currently know too much about command/result details
- printer-specific quirks may still be scattered in UI code
- package API can become too broad if you export everything
- local refactors will be noisier if you change both package boundary and app behavior at once

Mitigation:
- extraction should be mostly file moves plus import rewiring
- avoid behavior changes during package creation
- do protocol fixes in separate commits from package moves

## Recommended Commit Sequence

1. `refactor(protocol): centralize mqtt ack parsing`
2. `build(package): scaffold boomprint_connectivity package`
3. `refactor(protocol): move printer models into connectivity package`
4. `refactor(protocol): move mqtt and ftp clients into connectivity package`
5. `refactor(app): consume boomprint_connectivity package`
6. `test(protocol): add package-level mqtt and ftp coverage`

## Immediate Next Step

The best first step is:
- audit and centralize protocol-only helpers currently split between pages and `bambu_mqtt.dart`

That gives us a clean extraction target before we create the package.
