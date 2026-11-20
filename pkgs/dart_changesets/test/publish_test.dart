import 'dart:io';

import 'package:test/test.dart';

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/doctor.dart';
import 'package:dart_changesets/src/publish.dart';

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
  test('publish-tag fails usage on malformed tag', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'garbage',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag fails static check on version mismatch', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync('## 1.0.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v9.9.9',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag fails static check without changelog entry', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['0.1.0'],
        }),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag skips when pub.dev already has the version', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync('## 1.0.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['1.0.0'],
        }),
      );
      expect(code, 0);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag reports typed bootstrap for never-published packages',
      () async {
    final root = buildFixtureRepo(const {
      'fresh': FixturePackage(version: '0.1.0'),
    });
    File('${root.path}/pkgs/fresh/CHANGELOG.md').writeAsStringSync('## 0.1.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'fresh-v0.1.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitBootstrapNeeded);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag refuses publish_to:none packages', () async {
    final root = buildFixtureRepo(const {
      'private': FixturePackage(version: '1.0.0', publishToNone: true),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'private-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });
}
