import 'dart:io';

import 'package:test/test.dart';

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/doctor.dart';

import 'fixtures.dart';

final class FakePubDevClient implements PubDevClient {
  FakePubDevClient(this.packages);

  final Map<String, List<String>> packages;

  @override
  Future<PubDevInfo> lookup(String package) async {
    final versions = packages[package];
    if (versions == null) return PubDevInfo(status: PubDevStatus.newPackage);
    return PubDevInfo(status: PubDevStatus.exists, latestVersion: versions.last);
  }

  @override
  Future<List<String>> versions(String package) async =>
      packages[package] ?? const <String>[];
}

void main() {
  group('ChangesetsConfig', () {
    test('defaults', () {
      const config = ChangesetsConfig();
      expect(config.packagesDir, 'pkgs');
      expect(config.dependentBump, DependentBump.patch);
      expect(config.tagFor('a', '1.0.0'), 'a-v1.0.0');
      expect(config.parseTag('a-v1.0.0'), ('a', '1.0.0'));
      expect(config.parseTag('not-a-tag'), isNull);
    });

    test('custom tag format round-trips', () {
      const config = ChangesetsConfig(tagFormat: 'release-{package}-v{version}');
      expect(config.tagFor('pkg', '2.3.4'), 'release-pkg-v2.3.4');
      expect(config.parseTag('release-pkg-v2.3.4'), ('pkg', '2.3.4'));
      expect(config.parseTag('other-pkg-v2.3.4'), isNull);
    });

    test('loads yaml overrides', () {
      final file = File(
        '${Directory.systemTemp.path}/dcfg_${DateTime.now().microsecondsSinceEpoch}.yaml',
      )..writeAsStringSync(
          'packages_dir: packages\ndependent_bump: minor\nignore:\n  - x\n'
          'tag_format: "{package}=={version}"\n',
        );
      try {
        final config = ChangesetsConfig.loadFromFile(file.path);
        expect(config.packagesDir, 'packages');
        expect(config.dependentBump, DependentBump.minor);
        expect(config.ignore, {'x'});
        expect(config.tagFor('a', '1.0.0'), 'a==1.0.0');
      } finally {
        file.deleteSync();
      }
    });

    test('rejects unknown dependent_bump', () {
      final file = File(
        '${Directory.systemTemp.path}/dcfg_${DateTime.now().microsecondsSinceEpoch}.yaml',
      )..writeAsStringSync('dependent_bump: banana\n');
      try {
        expect(
          () => ChangesetsConfig.loadFromFile(file.path),
          throwsA(isA<FormatException>()),
        );
      } finally {
        file.deleteSync();
      }
    });
  });

  group('runDoctor', () {
    test('flags path deps, private deps, and missing files', () async {
      final root = buildFixtureRepo(const {
        'good': FixturePackage(version: '1.0.0'),
        'badpath': FixturePackage(
          version: '1.0.0',
          dependencies: {'good': '^1.0.0', 'sibling': '{path: ../good}'},
        ),
        'badprivate': FixturePackage(
          version: '1.0.0',
          dependencies: {'hidden': '^1.0.0'},
        ),
        'hidden': FixturePackage(version: '1.0.0', publishToNone: true),
      });
      try {
        final graph = await loadGraph(root.path);
        final report = await runDoctor(
          graph: graph,
          config: const ChangesetsConfig(),
          changesetsDir: '${root.path}/.changesets',
          pubDevClient: FakePubDevClient(const {
            'good': ['1.0.0'],
          }),
        );
        final codes = report.findings.map((f) => f.code).toSet();
        expect(codes, containsAll(<String>['path_dep_in_publishable', 'depends_on_private']));
        expect(report.hasErrors, isTrue);
        expect(report.census['good']!.status, PubDevStatus.exists);
        expect(report.census['badpath']!.status, PubDevStatus.newPackage);
      } finally {
        teardownRepo(root);
      }
    });

    test('clean fixture passes', () async {
      final root = buildFixtureRepo(const {
        'clean': FixturePackage(version: '1.0.0'),
      });
      File('${root.path}/pkgs/clean/README.md').writeAsStringSync('x');
      File('${root.path}/pkgs/clean/LICENSE').writeAsStringSync('x');
      File('${root.path}/pkgs/clean/CHANGELOG.md').writeAsStringSync('x');
      try {
        final graph = await loadGraph(root.path);
        final report = await runDoctor(
          graph: graph,
          config: const ChangesetsConfig(),
          changesetsDir: '${root.path}/.changesets',
          pubDevClient: FakePubDevClient(const {}),
        );
        expect(report.hasErrors, isFalse);
      } finally {
        teardownRepo(root);
      }
    });
  });
}
