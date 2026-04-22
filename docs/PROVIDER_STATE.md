# Provider State Guide

This app now uses `provider` for app-level state that should outlive a single
widget build and be shared across multiple screens.

The current first step is [lib/connection_controller.dart](/home/ry/code_flutter/rnd_bambu_rtsp/lib/connection_controller.dart),
which owns connection and printer-session state:

- active stream URL
- available camera streams
- selected camera index
- MQTT connection lifecycle
- printer status and merged print status
- chamber light state and optimistic confirmation window
- firmware warning state

`main.dart` still owns media-player and presentation concerns:

- `Player` / `VideoController`
- buffering and playback overlay UI
- stall monitor and reconnect timing
- screenshot capture
- transient widget-only flags like control overlay visibility

That split is intentional. `provider` is being used to remove cross-screen
session state from widgets, not to push every local UI flag into a
`ChangeNotifier`.

## Why Provider Here

The goal is not "use Provider because it is fashionable". The goal is:

- one clear owner for shared app state
- fewer static reads from `SettingsManager.settings`
- less protocol logic embedded directly in widgets
- better testability for connection and printer-state logic
- a path toward multiple printers, cloud/local modes, and richer help/error UI

For this codebase, `provider` is a pragmatic choice because it is:

- lightweight
- incremental
- easy to retrofit into an existing widget tree
- good enough for `ChangeNotifier`-style controllers

## Current Pattern

The root app provides the controller in [lib/main.dart](/home/ry/code_flutter/rnd_bambu_rtsp/lib/main.dart):

```dart
return ChangeNotifierProvider(
  create: (_) => ConnectionController(),
  child: MaterialApp(
    home: const StreamPage(),
  ),
);
```

Widgets should read state in two ways:

- `context.watch<T>()`
  Use when the widget must rebuild when controller state changes.

- `context.read<T>()`
  Use for one-off actions, side effects, or initialization where rebuilds are
  not wanted.

Example:

```dart
final connection = context.watch<ConnectionController>();
final titleSummary = _buildTitleSummary(connection.lastPrintStatus);
```

```dart
final connection = context.read<ConnectionController>();
await connection.startStreaming(url);
```

## What Belongs In A Controller

Good controller responsibilities:

- loading and caching app/session state
- coordinating services like MQTT or FTP
- transforming raw protocol events into UI-facing fields
- exposing commands such as connect, disconnect, switch camera, toggle light
- notifying listeners when shared state changes

Bad controller responsibilities:

- owning `BuildContext`
- rendering widgets
- keeping view-only animation flags
- platform view/controller instances that belong to a specific widget subtree
- becoming a giant "misc stuff" class

If a controller starts to accumulate unrelated concerns, split it.

## What To Extract Next

The next good candidates are:

1. `SettingsController`
   Own settings load/save/import/export/QR flows and expose the active printer
   profile as state rather than static reads.

2. `PrintStatusController`
   If print telemetry grows substantially beyond `ConnectionController`, split
   out nozzle, AMS, filament, and printer-state merging.

3. `HelpController` or repository-backed help service
   Resolve docs/resources based on firmware, printer events, and known errors.

## Rules For Future Work

When adding new shared state:

- prefer extending an existing controller only if the concern is truly related
- otherwise create a new controller and provide it alongside the existing one
- keep persistence in repositories/managers, not directly in widgets
- keep protocol parsing in service/controller layers, not in page widgets

When adding new UI:

- use `watch` for values that drive rendering
- use `read` for button actions and async workflows
- do not store duplicated copies of controller state in `State<T>` unless there
  is a clear UI-local reason

## Practical Example

The chamber light flow is a good example of what belongs in shared state:

- command goes through `ConnectionController.setChamberLight`
- optimistic state is applied there
- pending confirmation timer lives there
- later MQTT report reconciles the final value there
- widgets only display `connection.chamberLightOn`

That keeps the protocol-specific timing logic out of the UI.

## What Provider Does Not Solve

`provider` does not automatically fix architecture. It is still possible to
create an oversized `ChangeNotifier` that is just as hard to maintain as a
large widget.

The standard to aim for is:

- small controllers
- clear ownership
- minimal widget-local duplication
- services/repositories under controllers
- UI that mostly renders state and sends intent

That is the pattern to keep following in this repo.
