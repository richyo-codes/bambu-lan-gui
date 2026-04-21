import 'help_catalog.dart';

final class PrinterFirmwareWarning {
  final String firmwareVersion;
  final String message;
  final HelpEntry helpEntry;

  const PrinterFirmwareWarning({
    required this.firmwareVersion,
    required this.message,
    required this.helpEntry,
  });
}

String? extractFirmwareVersion(Map<String, dynamic> json) {
  const candidateKeys = <String>{
    'firmware_version',
    'firmwareVersion',
    'fw_version',
    'fwVersion',
    'firmware',
    'version',
  };
  final visited = <Object?>{};

  String? visit(dynamic node) {
    if (node == null || visited.contains(node)) {
      return null;
    }
    if (node is Map) {
      visited.add(node);
      for (final entry in node.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;
        final lowerKey = key.toLowerCase();
        final looksVersionKey =
            candidateKeys.contains(key) ||
            candidateKeys.contains(lowerKey) ||
            lowerKey.contains('firmware') ||
            lowerKey.contains('fw');
        if (looksVersionKey && value is String) {
          final normalized = value.trim();
          if (_looksLikeVersion(normalized)) {
            return normalized;
          }
        }
        final nested = visit(value);
        if (nested != null) {
          return nested;
        }
      }
      return null;
    }
    if (node is Iterable) {
      visited.add(node);
      for (final value in node) {
        final nested = visit(value);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  return visit(json);
}

PrinterFirmwareWarning? evaluateFirmwareWarning(String? firmwareVersion) {
  final version = firmwareVersion?.trim();
  if (version == null || version.isEmpty) {
    return null;
  }

  if (_compareVersionParts(
        _parseVersionParts(version),
        _minimumSupportedVersion,
      ) >=
      0) {
    return null;
  }

  final helpEntry =
      HelpCatalog.entryById('firmware-release-notes') ??
      HelpCatalog.entries.first;
  return PrinterFirmwareWarning(
    firmwareVersion: version,
    helpEntry: helpEntry,
    message:
        'Printer firmware $version is older than the recommended baseline. Chamber light and nozzle metadata may be incomplete or behave differently until the printer is updated.',
  );
}

HelpEntry? firmwareHelpEntry() =>
    HelpCatalog.entryById('firmware-release-notes');

bool _looksLikeVersion(String value) {
  return RegExp(r'^\d+(\.\d+){1,5}([-\+].*)?$').hasMatch(value);
}

List<int> _parseVersionParts(String value) {
  final parts = value.split(RegExp(r'[.\-_+]'));
  return parts.map((part) => int.tryParse(part) ?? 0).toList(growable: false);
}

int _compareVersionParts(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) {
      return left.compareTo(right);
    }
  }
  return 0;
}

const _minimumSupportedVersion = <int>[1, 8, 0, 0];
