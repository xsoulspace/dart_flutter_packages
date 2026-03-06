import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../registry/tools/_pubspec_rewriter.dart';
import '../registry/tools/_registry_workspace.dart';

void main() {
  group('package discovery', () {
    test('excludes publish_to none packages from publishable discovery', () async {
      final repoRoot = await _createRepoFixture();

      final publishable = await discoverPackages(
        repoRoot: repoRoot.path,
        includePrivate: false,
      );
      final allPackages = await discoverAllPackages(repoRoot: repoRoot.path);

      expect(publishable.map((final package) => package.name), ['public_pkg']);
      expect(
        allPackages.map((final package) => package.name),
        ['private_pkg', 'public_pkg'],
      );
      expect(allPackages.first.isPrivate, isTrue);
    });

    test('parses inline lists and nested pubspec structures with yaml package', () async {
      final repoRoot = await _createRepoFixture(
        publicPubspec: '''
name: public_pkg
description: Public package
version: 1.2.3
topics: [logging, registry]
environment:
  sdk: ">=3.11.0 <4.0.0"
dependencies:
  args: ^2.7.0
''',
      );

      final packages = await discoverPackages(
        repoRoot: repoRoot.path,
        includePrivate: false,
      );

      expect(packages.single.pubspecJson['topics'], ['logging', 'registry']);
      expect(
        packages.single.pubspecJson['environment'],
        {'sdk': '>=3.11.0 <4.0.0'},
      );
    });
  });

  group('archives', () {
    test('createPackageArchive is byte deterministic', () async {
      final packageDir = await Directory.systemTemp.createTemp(
        'xs-registry-archive-test-',
      );
      addTearDown(() async {
        if (packageDir.existsSync()) {
          await packageDir.delete(recursive: true);
        }
      });

      await File('${packageDir.path}/pubspec.yaml').writeAsString('''
name: archive_pkg
description: Archive package
version: 1.0.0
environment:
  sdk: ">=3.11.0 <4.0.0"
''');
      await Directory('${packageDir.path}/lib').create(recursive: true);
      await File('${packageDir.path}/lib/archive_pkg.dart').writeAsString(
        'library archive_pkg;\n',
      );
      await File('${packageDir.path}/pubspec_overrides.yaml').writeAsString(
        'dependency_overrides: {}\n',
      );

      final outputDir = await Directory.systemTemp.createTemp(
        'xs-registry-archive-output-',
      );
      addTearDown(() async {
        if (outputDir.existsSync()) {
          await outputDir.delete(recursive: true);
        }
      });

      final package = PackageInfo(
        name: 'archive_pkg',
        version: '1.0.0',
        directoryPath: packageDir.path,
        relativeDirectory: 'pkgs/archive_pkg',
        relativePubspecPath: 'pkgs/archive_pkg/pubspec.yaml',
        pubspecPath: '${packageDir.path}/pubspec.yaml',
        pubspecContent: await File('${packageDir.path}/pubspec.yaml').readAsString(),
        pubspecJson: <String, Object?>{
          'name': 'archive_pkg',
          'description': 'Archive package',
          'version': '1.0.0',
          'environment': {'sdk': '>=3.11.0 <4.0.0'},
        },
        publishTo: null,
      );

      final firstArchive = await createPackageArchive(
        package: package,
        outputDirectory: outputDir.path,
      );
      final firstBytes = await firstArchive.readAsBytes();
      final firstSha = await computeSha256Hex(firstArchive);

      await firstArchive.delete();

      final secondArchive = await createPackageArchive(
        package: package,
        outputDirectory: outputDir.path,
      );
      final secondBytes = await secondArchive.readAsBytes();
      final secondSha = await computeSha256Hex(secondArchive);

      expect(secondBytes, firstBytes);
      expect(secondSha, firstSha);
      expect(
        await listTrackedPackageFiles(package: package),
        ['lib/archive_pkg.dart', 'pubspec.yaml'],
      );
    });
  });

  group('rewrites', () {
    test('rewriteHostedDependencies rewrites only publishable internal packages', () {
      const content = '''
dependencies:
  public_pkg:
    path: ../public_pkg
  private_pkg:
    path: ../private_pkg
''';

      final result = rewriteHostedDependencies(
        content: content,
        internalPackageNames: {'public_pkg'},
        internalPackageVersions: {'public_pkg': '1.2.3'},
        hostedUrl: 'https://pub.xsoulspace.dev',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('name: public_pkg'));
      expect(result.content, contains('version: 1.2.3'));
      expect(result.content, contains('private_pkg:\n    path: ../private_pkg'));
    });
  });

  group('validation script', () {
    test('fails when stale metadata or archive files exist', () async {
      final repoRoot = await _createRepoFixture();
      final outputDir = await Directory.systemTemp.createTemp(
        'xs-registry-validate-output-',
      );
      addTearDown(() async {
        if (repoRoot.existsSync()) {
          await repoRoot.delete(recursive: true);
        }
        if (outputDir.existsSync()) {
          await outputDir.delete(recursive: true);
        }
      });

      final buildResult = await Process.run(Platform.resolvedExecutable, <String>[
        'registry/tools/build_registry_index.dart',
        '--repo-root',
        repoRoot.path,
        '--output-dir',
        outputDir.path,
        '--registry-base-url',
        'https://pub.xsoulspace.dev',
        '--github-repo',
        'xsoulspace/dart_flutter_packages',
      ], workingDirectory: _repoRootPath);
      expect(buildResult.exitCode, 0, reason: buildResult.stderr.toString());

      await File('${outputDir.path}/api/packages/zombie_pkg.json').writeAsString(
        jsonEncode(<String, Object?>{
          'name': 'zombie_pkg',
          'latest': {'version': '9.9.9'},
          'versions': [
            {'version': '9.9.9'},
          ],
        }),
      );
      await File('${outputDir.path}/archives/zombie_pkg-9.9.9.tar.gz')
          .writeAsBytes(const <int>[1, 2, 3]);

      final validateResult = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'registry/tools/validate_registry.dart',
          '--repo-root',
          repoRoot.path,
          '--output-dir',
          outputDir.path,
          '--registry-base-url',
          'https://pub.xsoulspace.dev',
          '--hosted-url',
          'https://pub.xsoulspace.dev',
        ],
        workingDirectory: _repoRootPath,
      );

      expect(validateResult.exitCode, isNonZero);
      expect(
        validateResult.stderr.toString(),
        contains('api/packages contents do not exactly match'),
      );
      expect(
        validateResult.stderr.toString(),
        contains('archives contents do not exactly match'),
      );
    });
  });

  group('semantic versions', () {
    test('sort prerelease and stable versions correctly', () {
      final versions = <SemanticVersion>[
        SemanticVersion.parse('1.0.0'),
        SemanticVersion.parse('1.0.0-beta.2'),
        SemanticVersion.parse('1.0.0-beta.1'),
        SemanticVersion.parse('1.0.0+5'),
      ]..sort();

      expect(
        versions.map((final version) => version.toString()).toList(),
        ['1.0.0-beta.1', '1.0.0-beta.2', '1.0.0', '1.0.0+5'],
      );
    });
  });
}

String get _repoRootPath => Directory.current.path;

Future<Directory> _createRepoFixture({
  final String? publicPubspec,
}) async {
  final repoRoot = await Directory.systemTemp.createTemp('xs-registry-repo-');
  final pkgsDir = Directory('${repoRoot.path}/pkgs');
  await pkgsDir.create(recursive: true);

  await _writePackage(
    pkgsDir.path,
    name: 'private_pkg',
    pubspec: '''
name: private_pkg
description: Private package
version: 0.1.0
publish_to: none
environment:
  sdk: ">=3.11.0 <4.0.0"
''',
  );
  await _writePackage(
    pkgsDir.path,
    name: 'public_pkg',
    pubspec: publicPubspec ??
        '''
name: public_pkg
description: Public package
version: 1.2.3
environment:
  sdk: ">=3.11.0 <4.0.0"
dependencies:
  args: ^2.7.0
''',
  );

  return repoRoot;
}

Future<void> _writePackage(
  final String pkgsDir, {
  required final String name,
  required final String pubspec,
}) async {
  final packageDir = Directory('$pkgsDir/$name');
  await packageDir.create(recursive: true);
  await File('${packageDir.path}/pubspec.yaml').writeAsString(pubspec);
  await Directory('${packageDir.path}/lib').create(recursive: true);
  await File('${packageDir.path}/lib/$name.dart').writeAsString(
    'library $name;\n',
  );
}
