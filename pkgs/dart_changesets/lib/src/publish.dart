import 'dart:async';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'config.dart';
import 'doctor.dart';
import 'workspace_graph.dart';

/// Exit codes used by the publish flow.
const publishExitUsage = 64;
const publishExitBootstrapNeeded = 65;
const publishExitDependencyTimeout = 66;
const publishExitPublishFailed = 67;
const publishExitWaitTimeout = 68;

/// Publishes the package named by a release tag, intentcall-style
/// (ported from `tool/intentcall/bin/intentcall.dart` `publishRelease`,
/// production-proven there; attribution: Arenukvern/intentcall).
///
/// Flow: static checks → skip-existing → bootstrap check → dependency wait
/// → strict dry-run → `publish --force` → wait for pub.dev visibility.
///
/// pub.dev's automated publishing is ref-gated per package tag: CI runs one
/// workflow per `<package>-v<version>` tag; ordering across a train emerges
/// from [dependency waits plus skip-existing re-runs](https://dart.dev/tools/pub/automated-publishing).
Future<int> publishTag(
  String repoRoot, {
  required ChangesetsConfig config,
  required WorkspaceGraph graph,
  required String tag,
  required bool execute,
  required bool skipExisting,
  required PubDevClient pubDevClient,
  Duration dependencyWait = const Duration(seconds: 240),
  Duration visibilityWait = const Duration(seconds: 300),
}) async {
  final parsed = config.parseTag(tag.trim());
  if (parsed == null) {
    stderr.writeln(
      'FAIL: tag "$tag" does not match tag format "${config.tagFormat}".',
    );
    return publishExitUsage;
  }
  final (packageName, versionRaw) = parsed;
  final version = Version.parse(versionRaw);

  // -- Static checks ------------------------------------------------------
  final pkg = graph.packages[packageName];
  if (pkg == null) {
    stderr.writeln(
      'FAIL: "$packageName" is not a workspace package under '
      '${config.packagesDir}/.',
    );
    return publishExitUsage;
  }
  if (!pkg.publishable) {
    stderr.writeln(
      'FAIL: "$packageName" is publish_to: none — it cannot be published.',
    );
    return publishExitUsage;
  }
  if (pkg.version != version) {
    stderr.writeln(
      'FAIL: tag version $versionRaw does not match pubspec version '
      '${pkg.version} for $packageName.',
    );
    return publishExitUsage;
  }
  final changelog = File('${pkg.directory}${Platform.pathSeparator}CHANGELOG.md');
  final changelogText = changelog.existsSync() ? changelog.readAsStringSync() : '';
  final versionHeading = RegExp(
    r'^##[ \t]+' + RegExp.escape(versionRaw) + r'\s*$',
    multiLine: true,
  );
  if (!versionHeading.hasMatch(changelogText)) {
    stderr.writeln(
      'FAIL: $packageName/CHANGELOG.md has no entry for $versionRaw.',
    );
    return publishExitUsage;
  }
  final pathDeps = pkg.dependencies.entries
      .where((e) => e.value.isPath)
      .map((e) => e.key)
      .toList();
  if (pathDeps.isNotEmpty) {
    stderr.writeln(
      'FAIL: $packageName declares path dependencies ($pathDeps) — '
      'publishable packages must use hosted constraints.',
    );
    return publishExitUsage;
  }

  // -- Skip-existing ------------------------------------------------------
  final info = await pubDevClient.lookup(packageName);
  if (info.status == PubDevStatus.exists &&
      await _hasVersion(pubDevClient, packageName, version)) {
    print('OK: pub.dev already exposes $packageName $versionRaw; skipping.');
    return 0;
  }

  // -- Bootstrap gate -----------------------------------------------------
  if (info.status == PubDevStatus.newPackage) {
    stderr.writeln('''
BOOTSTRAP REQUIRED: $packageName has never been published to pub.dev.
pub.dev cannot automate a package's first release:
  1. cd ${pkg.directory}
  2. dart pub publish        (or: flutter pub publish)
     — sign in with the uploader account in the browser when prompted
  3. On pub.dev, open $packageName → Admin → "Automated publishing",
     enable it for repository <owner>/<repo> with tag pattern
     "${config.tagFormat.replaceFirst('{package}', packageName).replaceFirst('{version}', '{{version}}')}"
  4. Re-run this publish (skip-existing keeps it idempotent).
''');
    return publishExitBootstrapNeeded;
  }
  if (info.status == PubDevStatus.lookupFailed) {
    stderr.writeln(
      'FAIL: could not reach pub.dev to check $packageName '
      '(network down? retry or run with the package present).',
    );
    return publishExitPublishFailed;
  }

  // -- Dependency wait ----------------------------------------------------
  final unsatisfied = <String, VersionConstraint>{};
  for (final entry in pkg.dependencies.entries) {
    final dep = graph.packages[entry.key];
    if (dep == null || !entry.value.isHosted || entry.value.constraint == null) {
      continue;
    }
    unsatisfied[entry.key] = VersionConstraint.parse(entry.value.constraint!);
  }
  if (unsatisfied.isNotEmpty) {
    final deadline = DateTime.now().add(dependencyWait);
    final pending = Map.of(unsatisfied);
    while (DateTime.now().isBefore(deadline) && pending.isNotEmpty) {
      for (final name in pending.keys.toList()) {
        final visible = await _visibleVersions(pubDevClient, name);
        if (visible == null) continue;
        final constraint = pending[name]!;
        final satisfied = visible.any((raw) {
          try {
            return constraint.allows(Version.parse(raw));
          } on FormatException {
            return false;
          }
        });
        if (satisfied) pending.remove(name);
      }
      if (pending.isEmpty) break;
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    if (pending.isNotEmpty) {
      stderr.writeln('''
FAIL: pub.dev does not yet expose versions of ${pending.keys.toList()}
      satisfying this package's constraints. An upstream release train is
      still landing. Re-run this publish after the dependency publishes
      (skip-existing keeps completed packages untouched).
''');
      return publishExitDependencyTimeout;
    }
  }

  // -- Strict dry-run -----------------------------------------------------
  final runner = pkg.isFlutter ? 'flutter' : 'dart';
  final dryRun = await Process.run(
    runner,
    const <String>['pub', 'publish', '--dry-run'],
    workingDirectory: pkg.directory,
  );
  if (dryRun.exitCode != 0) {
    stderr.writeln(
      'FAIL: strict publish dry-run for $packageName failed '
      '(exit ${dryRun.exitCode}):\n${dryRun.stdout}\n${dryRun.stderr}',
    );
    return publishExitPublishFailed;
  }

  if (!execute) {
    print('OK: publish-tag preflight complete (no publish performed).');
    return 0;
  }

  // -- Publish ------------------------------------------------------------
  final publish = await Process.run(
    runner,
    const <String>['pub', 'publish', '--force'],
    workingDirectory: pkg.directory,
  );
  if (publish.exitCode != 0) {
    stderr.writeln(
      'FAIL: publishing $packageName $versionRaw failed '
      '(exit ${publish.exitCode}):\n${publish.stdout}\n${publish.stderr}',
    );
    return publishExitPublishFailed;
  }

  // -- Visibility ---------------------------------------------------------
  final visibleDeadline = DateTime.now().add(visibilityWait);
  while (DateTime.now().isBefore(visibleDeadline)) {
    if (await _hasVersion(pubDevClient, packageName, version)) {
      print('OK: pub.dev exposes $packageName $versionRaw.');
      return 0;
    }
    await Future<void>.delayed(const Duration(seconds: 10));
  }
  stderr.writeln(
    'FAIL: publish command succeeded but $packageName $versionRaw did not '
    'appear on pub.dev within ${visibilityWait.inSeconds}s. Check the '
    'package page manually before re-running.',
  );
  return publishExitWaitTimeout;
}

Future<bool> _hasVersion(
  PubDevClient client,
  String package,
  Version version,
) async {
  final versions = await _visibleVersions(client, package);
  if (versions == null) return false;
  return versions.any((raw) {
    try {
      return Version.parse(raw) == version;
    } on FormatException {
      return false;
    }
  });
}

Future<List<String>?> _visibleVersions(PubDevClient client, String package) async {
  try {
    return await client.versions(package);
  } on Exception {
    return null;
  }
}
