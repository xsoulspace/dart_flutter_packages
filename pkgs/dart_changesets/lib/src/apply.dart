import 'dart:convert';
import 'dart:io';

import 'bump.dart';
import 'changeset.dart';
import 'config.dart';
import 'workspace_graph.dart';

/// Result of materializing a release train onto the working tree.
final class AppliedTrain {
  AppliedTrain({
    required this.plan,
    required this.writtenFiles,
    required this.consumedChangesets,
    required this.trainsFilePath,
  });

  final ReleasePlan plan;
  final List<String> writtenFiles;
  final List<String> consumedChangesets;

  /// Path of the JSON artifact listing the train's tags, written so CI can
  /// push one tag per package after the version PR merges.
  final String trainsFilePath;
}

const pendingTrainFileName = '.pending-train.json';

/// Applies a [plan] to the working tree: bumps pubspec versions, rewrites
/// dependent constraints (published and private), prepends changelog
/// sections, deletes consumed intent files, and writes the pending-train
/// artifact consumed by CI.
AppliedTrain applyPlan({
  required ReleasePlan plan,
  required List<String> consumedChangesetPaths,
  required String changesetsDir,
  required ChangesetsConfig config,
  required Map<String, Map<String, String>> privateRewrites,
}) {
  final written = <String>[];

  for (final release in plan.releases) {
    final pkg = release.package;

    // 1. Version bump.
    var content = pkg.pubspecContent;
    if (release.constraintRewrites.isNotEmpty) {
      for (final entry in release.constraintRewrites.entries) {
        final updated = rewriteConstraint(
          content,
          entry.key,
          entry.value,
        );
        if (updated == null) {
          throw StateError(
            'could not locate constraint for ${entry.key} in ${pkg.pubspecPath}',
          );
        }
        content = updated;
      }
    }
    content = rewriteVersion(content, release.newVersion);
    File(pkg.pubspecPath).writeAsStringSync(content);
    written.add(pkg.pubspecPath);

    // 2. Changelog section.
    final changelogPath =
        '${pkg.directory}${Platform.pathSeparator}CHANGELOG.md';
    final changelog = File(changelogPath);
    final existing =
        changelog.existsSync() ? changelog.readAsStringSync() : '';
    changelog.writeAsStringSync(
      prependChangelog(
        existing,
        version: release.newVersion.canonicalizedVersion,
        bumpType: release.bumpType,
        entries: release.changelogEntries,
      ),
    );
    written.add(changelogPath);
  }

  // 3. Private dependents: constraint-only rewrites (no release).
  for (final entry in privateRewrites.entries) {
    final pkgFile = File(entry.key);
    if (!pkgFile.existsSync()) {
      throw StateError('private dependent pubspec missing: ${entry.key}');
    }
    var content = pkgFile.readAsStringSync();
    for (final rewrite in entry.value.entries) {
      final updated = rewriteConstraint(
        content,
        rewrite.key,
        rewrite.value,
      );
      if (updated == null) {
        throw StateError(
          'could not locate constraint for ${rewrite.key} in ${entry.key}',
        );
      }
      content = updated;
    }
    pkgFile.writeAsStringSync(content);
    written.add(entry.key);
  }

  // 4. Pending-train artifact for CI (dependency order).
  final trainsPath =
      '$changesetsDir${Platform.pathSeparator}$pendingTrainFileName';
  final trainsJson = const JsonEncoder.withIndent('  ').convert(<Object?>[
    for (final release in plan.releases)
      <String, String>{
        'package': release.package.name,
        'version': release.newVersion.canonicalizedVersion,
        'tag': config.tagFor(
          release.package.name,
          release.newVersion.canonicalizedVersion,
        ),
        'directory': release.package.directory,
      },
  ]);
  File(trainsPath).writeAsStringSync('$trainsJson\n');
  written.add(trainsPath);

  // 5. Consume the intent files that produced this train.
  for (final path in consumedChangesetPaths) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  return AppliedTrain(
    plan: plan,
    writtenFiles: written,
    consumedChangesets: consumedChangesetPaths,
    trainsFilePath: trainsPath,
  );
}

/// Prepends a release section to changelog content, under a leading `#`
/// header when present.
String prependChangelog(
  String existing, {
  required String version,
  required BumpType bumpType,
  required List<String> entries,
}) {
  final section = buildChangelogSection(
    version: version,
    bumpType: bumpType,
    entries: entries,
  );
  if (existing.isEmpty) {
    return '$section\n';
  }
  final lines = existing.split('\n');
  if (lines.first.startsWith('# ')) {
    // Insert after the header (and any immediately following blank lines).
    var insertAt = 1;
    while (insertAt < lines.length && lines[insertAt].trim().isEmpty) {
      insertAt++;
    }
    final head = lines.sublist(0, insertAt).join('\n');
    final tail = lines.sublist(insertAt).join('\n');
    return '$head\n$section\n${tail.isEmpty ? '' : '$tail\n'}';
  }
  return '$section\n$existing';
}

/// Renders one release section, changesets-style:
/// grouped under Major/Minor/Patch Changes by bump type.
String buildChangelogSection({
  required String version,
  required BumpType bumpType,
  required List<String> entries,
}) {
  final sectionName = switch (bumpType) {
    BumpType.major => 'Major Changes',
    BumpType.minor => 'Minor Changes',
    BumpType.patch => 'Patch Changes',
  };
  final buffer = StringBuffer('## $version\n\n### $sectionName\n\n');
  for (final entry in entries) {
    final lines = entry.split('\n');
    buffer.writeln('- ${lines.first}');
    for (final line in lines.skip(1)) {
      buffer.writeln('  $line');
    }
  }
  return buffer.toString().trimRight();
}
