import 'help_catalog_data.dart';

enum HelpCategory { firmware, setup, printing, troubleshooting, reference }

final class HelpLink {
  final String label;
  final String url;

  const HelpLink({required this.label, required this.url});
}

final class HelpEntry {
  final String id;
  final String title;
  final String summary;
  final HelpCategory category;
  final List<String> matchCodes;
  final List<String> matchPhrases;
  final List<String> suggestedFixes;
  final List<HelpLink> links;

  const HelpEntry({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    this.matchCodes = const [],
    this.matchPhrases = const [],
    this.suggestedFixes = const [],
    this.links = const [],
  });

  bool matchesCode(String code) {
    final needle = code.trim().toLowerCase();
    return matchCodes.any((value) => value.toLowerCase() == needle);
  }

  bool matchesText(String text) {
    final haystack = text.trim().toLowerCase();
    if (haystack.isEmpty) {
      return false;
    }
    return matchCodes.any(haystack.contains) ||
        matchPhrases.any(haystack.contains);
  }
}

abstract final class HelpCatalog {
  static const List<HelpEntry> entries = defaultHelpEntries;

  static HelpEntry? entryById(String id) {
    final needle = id.trim().toLowerCase();
    if (needle.isEmpty) {
      return null;
    }
    for (final entry in entries) {
      if (entry.id.toLowerCase() == needle) {
        return entry;
      }
    }
    return null;
  }

  static List<HelpEntry> findByCode(String code) {
    if (code.trim().isEmpty) {
      return const [];
    }
    return entries
        .where((entry) => entry.matchesCode(code))
        .toList(growable: false);
  }

  static List<HelpEntry> findByText(String text) {
    if (text.trim().isEmpty) {
      return const [];
    }
    return entries
        .where((entry) => entry.matchesText(text))
        .toList(growable: false);
  }

  static HelpEntry? firstMatch({String? code, String? text}) {
    if (code != null && code.trim().isNotEmpty) {
      final matches = findByCode(code);
      if (matches.isNotEmpty) {
        return matches.first;
      }
    }
    if (text != null && text.trim().isNotEmpty) {
      final matches = findByText(text);
      if (matches.isNotEmpty) {
        return matches.first;
      }
    }
    return null;
  }
}
