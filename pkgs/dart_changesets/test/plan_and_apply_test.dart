import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:dart_changesets/src/bump.dart';
import 'package:dart_changesets/src/changeset.dart';
import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/apply.dart';

import 'fixtures.dart';

Changeset writeChangeset(
  Directory root,
  String name,
  String frontmatter, [
  String body = 'Some change.',
]) {
  final dir = Directory('${root.path}${Platform.pathSeparator}.changesets')
    ..createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name.md');
  file.writeAsStringSync('---\n$frontmatter---\n\n$body\n');
  return Changeset.fromFile(file.path);
}

void main() {
  group('bumpVersion', () {
    test('major leaves 0.x via 1.0.0', () {
      expect(
        bumpVersion(Version.parse('0.9.0'), BumpType.major).toString(),
        '1.0.0',
      );
    });

    test('minor rolls y on 0.x', () {
      expect(
        bumpVersion(Version.parse('0.9.0'), BumpType.minor).toString(),
        '0.10.0',
      );
    });

    test('patch increments', () {
      expect(
        bumpVersion(Version.parse('1.2.3'), BumpType.patch).toString(),
        '1.2.4',
      );
    });
  });

  group('computePlan', () {
    test('single declared bump, no dependents', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.2.3')});
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'a': minor\n", 'Add feature.'),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases, hasLength(1));
        expect(plan.releases.first.newVersion.toString(), '1.3.0');
        expect(plan.releases.first.changelogEntries, ['Add feature.']);
        expect(plan.releases.first.isDependentBump, isFalse);
      } finally {
        teardownRepo(root);
      }
    });

    test('0.x minor bump cascades through incompatible caret (0.x semantics)',
        () async {
      final root = buildFixtureRepo(const {
        'interface': FixturePackage(version: '0.9.0'),
        'impl': FixturePackage(
          version: '0.5.0',
          dependencies: {'interface': '^0.9.0'},
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'interface': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name).toList(), [
          'interface',
          'impl',
        ]);
        expect(plan.releases[0].newVersion.toString(), '0.10.0');
        // impl's ^0.9.0 does NOT allow 0.10.0 → dependent patch bump.
        expect(plan.releases[1].newVersion.toString(), '0.5.1');
        expect(plan.releases[1].isDependentBump, isTrue);
        expect(
          plan.releases[1].constraintRewrites['interface'],
          '^0.10.0',
        );
        expect(
          plan.releases[1].changelogEntries,
          ['Updated `interface` dependency constraint to `^0.10.0`.'],
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('satisfied constraint does not cascade', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.2.0'),
        'app': FixturePackage(
          version: '3.0.0',
          dependencies: {'core': '>=1.0.0 <2.0.0'},
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'core': patch\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name), ['core']);
      } finally {
        teardownRepo(root);
      }
    });

    test('private dependent gets constraint rewrite but no release', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.0.0'),
        'internal': FixturePackage(
          version: '1.0.0',
          dependencies: {'core': '^1.0.0'},
          publishToNone: true,
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'core': major\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name), ['core']);
        expect(plan.privateConstraintRewrites['internal']?['core'], '^2.0.0');
      } finally {
        teardownRepo(root);
      }
    });

    test('unknown package in changeset raises', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.0.0')});
      try {
        final graph = await loadGraph(root.path);
        expect(
          () => computePlan(
            graph: graph,
            changesets: [
              writeChangeset(root, 'one', "'nope': patch\n"),
            ],
            config: const ChangesetsConfig(),
          ),
          throwsA(isA<PlanException>()),
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('higher bump wins across changesets', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.0.0')});
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'a': patch\n"),
            writeChangeset(root, 'two', "'a': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.first.newVersion.toString(), '1.1.0');
      } finally {
        teardownRepo(root);
      }
    });

    test('releases order dependencies before dependents', () async {
      // 0.x carets cascade on minor bumps, so leaf's minor forces mid
      // (dependent patch) while top's declared minor rides along.
      final root = buildFixtureRepo(const {
        'leaf': FixturePackage(version: '0.1.0'),
        'mid': FixturePackage(version: '0.2.0', dependencies: {'leaf': '^0.1.0'}),
        'top': FixturePackage(version: '0.3.0', dependencies: {'mid': '^0.2.0'}),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'top': minor\n'leaf': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name).toList(), [
          'leaf',
          'mid',
          'top',
        ]);
        expect(plan.releases[0].newVersion.toString(), '0.2.0');
        expect(plan.releases[1].newVersion.toString(), '0.2.1');
        expect(plan.releases[2].newVersion.toString(), '0.4.0');
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('applyPlan', () {
    test('writes versions, constraints, changelogs, and the train artifact',
        () async {
      final root = buildFixtureRepo(const {
        'interface': FixturePackage(version: '0.9.0'),
        'impl': FixturePackage(
          version: '0.5.0',
          dependencies: {'interface': '^0.9.0'},
        ),
      });
      final changeset = writeChangeset(root, 'one', "'interface': minor\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(),
        );
        final applied = applyPlan(
          plan: plan,
          consumedChangesetPaths: [changeset.path],
          changesetsDir:
              '${root.path}${Platform.pathSeparator}.changesets',
          config: const ChangesetsConfig(),
          privateRewrites: plan.privateConstraintRewrites,
        );

        final interfacePubspec =
            File('${root.path}/pkgs/interface/pubspec.yaml').readAsStringSync();
        expect(interfacePubspec, contains('version: 0.10.0'));

        final implPubspec =
            File('${root.path}/pkgs/impl/pubspec.yaml').readAsStringSync();
        expect(implPubspec, contains('version: 0.5.1'));
        expect(implPubspec, contains('interface: ^0.10.0'));

        final implChangelog =
            File('${root.path}/pkgs/impl/CHANGELOG.md').readAsStringSync();
        expect(implChangelog, contains('## 0.5.1'));
        expect(implChangelog, contains('Patch Changes'));
        expect(implChangelog, contains('Updated `interface` dependency'));

        expect(File(changeset.path).existsSync(), isFalse);
        final train = File(applied.trainsFilePath).readAsStringSync();
        expect(train, contains('"package": "interface"'));
        expect(train, contains('"version": "0.10.0"'));
      } finally {
        teardownRepo(root);
      }
    });

    test('changelog inserts under an existing header', () {
      const existing = '# Changelog\n\n## 0.9.0\n\n- old\n';
      final updated = prependChangelog(
        existing,
        version: '0.10.0',
        bumpType: BumpType.minor,
        entries: const ['New feature.'],
      );
      expect(
        updated,
        startsWith('# Changelog\n\n## 0.10.0'),
      );
      expect(updated, contains('## 0.9.0'));
    });
  });
}
