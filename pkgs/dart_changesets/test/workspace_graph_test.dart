import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/workspace_graph.dart';

import 'fixtures.dart';

void main() {
  group('WorkspaceGraph.load', () {
    test('discovers packages, versions, and publishability', () async {
      final root = buildFixtureRepo(const {
        'a': FixturePackage(version: '1.2.3'),
        'b': FixturePackage(version: '0.9.0', publishToNone: true),
      });
      try {
        final graph = await loadGraph(root.path);
        expect(graph.packages.length, 2);
        expect(graph.packages['a']!.publishable, isTrue);
        expect(graph.packages['a']!.version.toString(), '1.2.3');
        expect(graph.packages['b']!.publishable, isFalse);
        expect(graph.publishable.map((pkg) => pkg.name), ['a']);
      } finally {
        teardownRepo(root);
      }
    });

    test('reads plain hosted, sdk, and path dependency forms', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.0.0'),
        'ui': FixturePackage(
          version: '2.0.0',
          dependencies: {
            'core': '^1.0.0',
            'flutter': '{sdk: flutter}',
            'local': '{path: ../core}',
          },
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final ui = graph.packages['ui']!;
        expect(ui.dependencies['core']!.isHosted, isTrue);
        expect(ui.dependencies['core']!.constraint, '^1.0.0');
        expect(ui.dependencies['flutter']!.isSdk, isTrue);
        expect(ui.dependencies['local']!.isPath, isTrue);
        expect(ui.isFlutter, isTrue);
        expect(graph.reverseDependents('core').map((pkg) => pkg.name), ['ui']);
      } finally {
        teardownRepo(root);
      }
    });

    test('reads nested hosted-url and dev dependency forms', () async {
      final root = Directory.systemTemp.createTempSync('dcg_nested_');
      Directory('${root.path}/pkgs/core').createSync(recursive: true);
      Directory('${root.path}/pkgs/dep').createSync(recursive: true);
      File('${root.path}/pkgs/core/pubspec.yaml').writeAsStringSync(
        'name: core\nversion: 1.0.0\n',
      );
      File('${root.path}/pkgs/dep/pubspec.yaml').writeAsStringSync(
        'name: dep\nversion: 1.0.0\ndev_dependencies:\n  core:\n'
        '    hosted:\n      name: core\n      url: https://example.dev\n'
        '    version: ^1.0.0\n',
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(),
        );
        final dep = graph.packages['dep']!;
        expect(dep.devDependencies['core']!.isHosted, isTrue);
        expect(dep.devDependencies['core']!.hostedUrl, 'https://example.dev');
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('pubspec text rewrites', () {
    test('rewriteVersion preserves comments and formatting', () {
      const content = 'name: x\nversion: 1.2.3 # pinned\nenvironment:\n  sdk: ^3.14.0\n';
      final updated = rewriteVersion(
        content,
        Version.parse('2.0.0'),
      );
      expect(updated, contains('version: 2.0.0 # pinned'));
    });

    test('rewriteConstraint handles plain form', () {
      const content = 'dependencies:\n  core: ^1.0.0\n  http: ^1.6.0\n';
      final updated = rewriteConstraint(content, 'core', '^1.1.0');
      expect(updated, contains('core: ^1.1.0'));
      expect(updated, contains('http: ^1.6.0'));
    });

    test('rewriteConstraint handles nested hosted form', () {
      const content = 'dependencies:\n  core:\n    hosted:\n      name: core\n'
          '      url: https://example.dev\n    version: ^1.0.0\n';
      final updated = rewriteConstraint(content, 'core', '^1.1.0');
      expect(updated, contains('version: ^1.1.0'));
    });

    test('rewriteConstraint returns null when absent', () {
      const content = 'dependencies:\n  other: ^1.0.0\n';
      expect(rewriteConstraint(content, 'core', '^1.1.0'), isNull);
    });
  });
}
