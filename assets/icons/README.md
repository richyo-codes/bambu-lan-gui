Icon variants for launcher generation

Files

- SVG sources: `assets/icons/*.svg`
- PNG renders (generated): `assets/icons/renders/*.png`

Exporting PNGs

- Requires `inkscape` or `rsvg-convert` installed locally.
- Run: `bash tool/export_icons.sh 1024`

Generating launcher icons (via flutter_launcher_icons)

1) Ensure PNGs exist (see exporting step above).
2) Install deps: `flutter pub get`
3) Generate a flavor (examples):
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor filament`
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor home`
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor lan`
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor stream`
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor cube`
   - `flutter pub run flutter_launcher_icons -f pubspec.yaml --flavor lan_shield`

Notes

- You can change sizes by passing a different number to the export script.
- All platforms are enabled in `pubspec.yaml` per flavor (android, ios, web, macos, windows, linux).
- If you prefer a different color palette or shape tweaks, edit the SVGs and re-export.
