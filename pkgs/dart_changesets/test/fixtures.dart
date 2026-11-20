import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/workspace_graph.dart';

/// Builds a synthetic repository on disk for engine tests. Returns the repo
/// root. Callers must clean up (helper in `teardown`).
Directory buildFixtureRepo(Map<String, FixturePackage> packages) {
  final root = Directory.systemTemp.createTempSync('dart_changesets_test_');
  for (final entry in packages.entries) {
    final dir = Directory(p.join(root.path, 'pkgs', entry.key))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
      entry.value.pubspec(entry.key),
    );
  }
  return root;
}

final class FixturePackage {
  const FixturePackage({
    required this.version,
    this.dependencies = const {},
    this.devDependencies = const {},
    this.publishToNone = false,
    this.flutter = false,
  });

  final String version;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;
  final bool publishToNone;
  final bool flutter;

  String pubspec(String name) {
    final buffer = StringBuffer()
      ..writeln('name: $name')
      ..writeln('version: $version')
      ..writeln('description: fixture')
      ..writeln('environment:')
      ..writeln('  sdk: ^3.14.0');
    if (publishToNone) buffer.writeln('publish_to: none');
    String deps(Map<String, String> map) {
      if (map.isEmpty) return '';
      final out = StringBuffer()..writeln();
      for (final entry in map.entries) {
        // Quote multi-word constraints so the generated pubspec stays valid
        // YAML; flow-map forms ({sdk: …}, {path: …}) pass through as-is.
        final value = entry.value;
        final needsQuote =
            value.contains(' ') && !value.startsWith('{');
        final rendered = needsQuote ? "'$value'" : value;
        out.writeln('  ${entry.key}: $rendered');
      }
      return out.toString().trimRight();
    }

    final regular = deps(dependencies);
    if (regular.isNotEmpty) {
      buffer
        ..writeln('dependencies:')
        ..writeln(regular);
    }
    final dev = deps(devDependencies);
    if (dev.isNotEmpty) {
      buffer
        ..writeln('dev_dependencies:')
        ..writeln(dev);
    }
    if (flutter) {
      buffer
        ..writeln()
        ..writeln('  # flutter marker for the runner probe')
        ..writeln('  # (real flutter packages have a flutter sdk dep)');
    }
    return buffer.toString();
  }
}

Future<WorkspaceGraph> loadGraph(String repoRoot) =>
    WorkspaceGraph.load(repoRoot, const ChangesetsConfig());

void teardownRepo(Directory root) {
  root.deleteSync(recursive: true);
}
