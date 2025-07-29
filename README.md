# Printer LAN

LAN-only helper to view a Bambu Lab printer camera stream and monitor telemetry. The app generates RTSP/RTSPS URLs for local playback and lets you save/import settings as JSON.

This is not an official Bambu Lab application. Use at your own risk.

## Printer Requirements (Bambu X1C)

To access the camera stream from the LAN, one of the following must be true:

- Developer Mode is enabled on the printer, which reveals the LAN RTSP/RTSPS stream and a per-printer code shown on the touchscreen.
- Your printer runs an older firmware that still exposes RTSP/RTSPS without Developer Mode. If you know the exact cutoff for your device, use that; otherwise, enable Developer Mode.

Notes:
- The app’s “Bambu X1C” URL template expects the printer’s special (developer) code and the printer’s LAN IP address.
- Newer firmware typically requires Developer Mode for LAN camera access.

## Risks of Enabling Developer Mode

Enabling Developer Mode relaxes some security protections intended for regular users. Typical risks include:

- Increased attack surface: extra services/ports may become accessible on the LAN.
- Network exposure: anyone on the same LAN who knows/obtains the code and IP could attempt to access the stream.
- Support implications: using undocumented/developer features may not be supported by the vendor and could affect warranty or support responses.
- Updates may change behavior: future firmware may alter, restrict, or remove these capabilities.

Mitigations:
- Keep the printer on a trusted LAN (or an isolated VLAN) and avoid exposing it to the internet.
- Use strong Wi‑Fi security and restrict who can join the network.
- Disable Developer Mode when not in use.

## How To Enable Developer Mode (high level)

On the printer touchscreen, open Settings and look for Developer Mode (or a similarly named option). When enabled, the screen will show a special code. You will also need the printer’s local IP address.

The exact menu names can vary by firmware; consult your printer’s documentation or on‑device help if options have moved between versions.

## Using This App

1. Open Settings (gear icon on the Stream Settings screen).
2. Select URL Format:
   - Bambu X1C: enter Special Code and Printer IP.
   - Generic RTSP: enter Printer IP (path is generic `rtsp://<ip>:554/stream`).
   - Custom: provide a full RTSP/RTSPS URL.
3. Save or Connect.

The app previews the generated URL for the selected format.

### Import/Export Settings

- Import: Use the Import button (AppBar or footer) to choose a `.json` file. The app accepts both camelCase keys and legacy `rtsp_*` keys.
- Export: Use the Export button to save current settings to a `.json` file. A toast will show the save location when available.

### Where Settings Are Stored

- SharedPreferences: basic key‑value copy for compatibility.
- JSON file: `rtsp_settings.json` inside the platform’s application support directory (mobile/desktop). On web, file I/O is skipped.

## Platforms

- Android, Linux, Windows.

## Disclaimer

This software targets LAN use only. Respect local laws, your device’s EULA/warranty terms, and your network security policies. You are responsible for any changes you make to your printer (including enabling Developer Mode) and their consequences.
