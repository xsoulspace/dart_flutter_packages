import 'dart:io';

import 'package:yaml/yaml.dart';

/// How aggressively a changeset intends to release a package.
enum BumpType {
  major,
  minor,
  patch;

  static BumpType fromString(String value) => switch (value) {
        'major' => BumpType.major,
        'minor' => BumpType.minor,
        'patch' => BumpType.patch,
        _ => throw ChangesetParseException(
            'Unknown bump type "$value" (expected major, minor, or patch).',
          ),
      };

  /// Higher bumps win when the same package is declared in several changesets.
  int get rank => switch (this) {
        BumpType.major => 3,
        BumpType.minor => 2,
        BumpType.patch => 1,
      };
}

/// A pending release-intent file under `.changesets/`.
final class Changeset {
  Changeset({
    required this.path,
    required this.body,
    required this.bumps,
  });

  /// Absolute path of the intent file.
  final String path;

  /// Changelog prose (trimmed, may be multi-line).
  final String body;

  /// Declared release intent: package name → bump type.
  final Map<String, BumpType> bumps;

  /// Parses one `.changesets/*.md` file.
  ///
  /// Format mirrors changesets: YAML frontmatter between `---` fences mapping
  /// quoted package names to bump types, followed by markdown prose.
  static Changeset parse(String path, String content) {
    final pattern = RegExp(r'^---\s*$', multiLine: true);
    final first = pattern.firstMatch(content);
    if (first == null) {
      throw ChangesetParseException(
        '$path: missing YAML frontmatter (expected a "---" fence at the top).',
      );
    }
    final secondStart = content.indexOf('\n---', first.end);
    if (secondStart < 0) {
      throw ChangesetParseException(
        '$path: frontmatter is not closed by a second "---" fence.',
      );
    }
    final frontmatter = content.substring(first.end, secondStart);
    final bodyStart = content.indexOf('\n', secondStart + 4);
    final body = bodyStart < 0 ? '' : content.substring(bodyStart + 1).trim();

    final doc = loadYamlNode(frontmatter);
    if (doc is! YamlMap || doc.keys.isEmpty) {
      throw ChangesetParseException(
        '$path: frontmatter must map package names to bump types.',
      );
    }
    final bumps = <String, BumpType>{};
    for (final entry in doc.entries) {
      final name = entry.key.toString();
      final raw = entry.value?.toString() ?? '';
      if (raw.isEmpty) {
        throw ChangesetParseException(
          '$path: package "$name" has no bump type.',
        );
      }
      bumps[name] = BumpType.fromString(raw);
    }
    return Changeset(path: path, body: body, bumps: bumps);
  }

  static Changeset fromFile(String path) =>
      parse(path, File(path).readAsStringSync());

  /// Loads every pending intent file from [changesetsDir], sorted by path.
  ///
  /// `README.md` and dot-files are documentation/artifacts, not intents, and
  /// are skipped.
  static List<Changeset> loadPending(String changesetsDir) {
    final dir = Directory(changesetsDir);
    if (!dir.existsSync()) return const <Changeset>[];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final base = f.uri.pathSegments.last;
          return base.endsWith('.md') &&
              base != 'README.md' &&
              !base.startsWith('.');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final f in files) Changeset.fromFile(f.path),
    ];
  }
}

/// Raised when an intent file cannot be parsed.
class ChangesetParseException implements Exception {
  ChangesetParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
