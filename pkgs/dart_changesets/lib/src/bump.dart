import 'package:pub_semver/pub_semver.dart';

import 'changeset.dart';
import 'config.dart';
import 'workspace_graph.dart';

/// One package's planned release inside a version train.
final class PlannedRelease {
  PlannedRelease({
    required this.package,
    required this.newVersion,
    required this.bumpType,
    required this.changelogEntries,
    required this.isDependentBump,
    required this.constraintRewrites,
  });

  final WorkspacePackage package;
  final Version newVersion;

  /// Declared bump, or the dependent-bump policy for cascaded packages.
  final BumpType bumpType;

  /// Changelog bullet lines (prose from changesets + dependency notes).
  final List<String> changelogEntries;

  /// True when this release exists only because a dependency constraint
  /// changed (changesets' "dependent bump").
  final bool isDependentBump;

  /// Constraint rewrites applied to THIS package's pubspec: dependency name
  /// → new constraint (populated when a dependency released a version this
  /// package's old constraint no longer allows).
  final Map<String, String> constraintRewrites;
}

/// The computed release train, in dependency order (dependencies before
/// dependents) so tags can be pushed and published in a safe order.
final class ReleasePlan {
  ReleasePlan({
    required this.releases,
    required this.privateConstraintRewrites,
    required this.errors,
  });

  final List<PlannedRelease> releases;

  /// Constraint rewrites for PRIVATE dependents (no release, but their
  /// workspace resolution must still admit the new version): package name →
  /// {dependency name → new constraint}.
  final Map<String, Map<String, String>> privateConstraintRewrites;

  /// Non-fatal anomalies surfaced during planning.
  final List<String> errors;

  bool get isEmpty => releases.isEmpty;
}

/// Raised when the plan cannot be computed (unknown package in an intent
/// file, ambiguous declarations, …).
class PlanException implements Exception {
  PlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Computes the release train from pending [changesets] over [graph].
ReleasePlan computePlan({
  required WorkspaceGraph graph,
  required List<Changeset> changesets,
  required ChangesetsConfig config,
}) {
  // 1. Collapse declared intents: max bump per package; prose preserved in
  //    declaration order.
  final declaredBumps = <String, BumpType>{};
  final proseByPackage = <String, List<String>>{};
  for (final changeset in changesets) {
    for (final entry in changeset.bumps.entries) {
      final package = entry.key;
      if (!graph.packages.containsKey(package)) {
        throw PlanException(
          'changeset ${changeset.path} declares unknown package "$package". '
          'Known: ${graph.packages.keys.toList()..sort()}',
        );
      }
      final existing = declaredBumps[package];
      if (existing == null || entry.value.rank > existing.rank) {
        declaredBumps[package] = entry.value;
      }
      final body = changeset.body.trim();
      if (body.isNotEmpty) {
        (proseByPackage[package] ??= <String>[]).add(body);
      }
    }
  }
  if (declaredBumps.isEmpty) {
    return ReleasePlan(
      releases: const <PlannedRelease>[],
      privateConstraintRewrites: const <String, Map<String, String>>{},
      errors: const <String>[],
    );
  }
  for (final ignored in config.ignore) {
    declaredBumps.remove(ignored);
  }

  final plannedVersions = <String, Version>{};
  final plannedEntries = <String, PlannedRelease>{};
  // Dependent pkg name → {dependency name → new constraint}; consumed when
  // the dependent itself is processed.
  final pendingRewrites = <String, Map<String, String>>{};
  final pendingNotes = <String, List<String>>{};
  final privateRewrites = <String, Map<String, String>>{};
  final errors = <String>[];

  final dependentBumpType = config.dependentBump == DependentBump.minor
      ? BumpType.minor
      : BumpType.patch;

  final queue = declaredBumps.keys.toList()..sort();
  final processed = <String>{};

  while (queue.isNotEmpty) {
    final name = queue.removeAt(0);
    if (!processed.add(name)) continue;
    final pkg = graph.packages[name]!;
    final declared = declaredBumps[name];
    final current = plannedVersions[name] ?? pkg.version;
    final newVersion = bumpVersion(
      current,
      declared ?? dependentBumpType,
    );

    // 2. Check every dependent of this package against its new version.
    for (final dependent in graph.reverseDependents(name)) {
      final ref = dependent.dependencyOn(name)!;
      if (!ref.isHosted || ref.constraint == null) {
        if (ref.isPath && dependent.publishable) {
          errors.add(
            '${dependent.name} depends on $name via path — publishable '
            'packages must use hosted constraints (doctor gate).',
          );
        }
        continue;
      }
      final constraint = VersionConstraint.parse(ref.constraint!);
      if (constraint.allows(newVersion)) continue;
      final newConstraint = '^${newVersion.canonicalizedVersion}';
      if (!dependent.publishable || config.ignore.contains(dependent.name)) {
        // Private dependents get constraint updates but never release.
        (privateRewrites[dependent.name] ??= <String, String>{})[name] =
            newConstraint;
        continue;
      }
      (pendingRewrites[dependent.name] ??= <String, String>{})[name] =
          newConstraint;
      (pendingNotes[dependent.name] ??= <String>[]).add(
        'Updated `$name` dependency constraint to `$newConstraint`.',
      );
      if (!plannedVersions.containsKey(dependent.name)) {
        plannedVersions[dependent.name] = dependent.version;
        queue.add(dependent.name);
      }
    }

    final entries = <String>[
      ...?proseByPackage[name],
      ...?pendingNotes.remove(name),
    ];
    plannedVersions[name] = newVersion;
    plannedEntries[name] = PlannedRelease(
      package: pkg,
      newVersion: newVersion,
      bumpType: declared ?? dependentBumpType,
      changelogEntries: entries,
      isDependentBump: declared == null,
      constraintRewrites: pendingRewrites.remove(name) ?? const <String, String>{},
    );
  }

  // 3. Dependency order: dependencies release before dependents.
  final ordered = _topoSort(plannedEntries.values.toList(), errors);
  return ReleasePlan(
    releases: ordered,
    privateConstraintRewrites: privateRewrites,
    errors: errors,
  );
}

/// Bumps [current] according to Dart/pub semver conventions: `major` leaves
/// 0.x (0.9.0 → 1.0.0); `minor` on 0.y rolls y (0.9.0 → 0.10.0).
Version bumpVersion(Version current, BumpType type) => switch (type) {
      BumpType.major => Version(current.major + 1, 0, 0),
      BumpType.minor => Version(current.major, current.minor + 1, 0),
      BumpType.patch => Version(current.major, current.minor, current.patch + 1),
    };

/// Orders releases so dependencies come before dependents. Cycles surface as
/// errors rather than infinite loops.
List<PlannedRelease> _topoSort(List<PlannedRelease> releases, List<String> errors) {
  final names = releases.map((r) => r.package.name).toSet();
  final byName = {for (final r in releases) r.package.name: r};
  final edges = <String, Set<String>>{
    for (final r in releases)
      r.package.name: {
        for (final dep in r.package.dependencies.keys)
          if (names.contains(dep)) dep,
      },
  };
  final ordered = <PlannedRelease>[];
  final visiting = <String>{};
  final visited = <String>{};

  void visit(String name) {
    if (visited.contains(name)) return;
    if (!visiting.add(name)) {
      errors.add('dependency cycle among released packages involving $name');
      return;
    }
    for (final dep in edges[name] ?? const <String>{}) {
      visit(dep);
    }
    visiting.remove(name);
    visited.add(name);
    final release = byName[name];
    if (release != null) ordered.add(release);
  }

  for (final name in names) {
    visit(name);
  }
  return ordered;
}
