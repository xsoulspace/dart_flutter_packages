import 'dart:convert';
import 'dart:io';

import '_registry_workspace.dart';

Future<void> main(final List<String> args) async {
  final options = _BuildOptions.parse(args);
  final allPackages = await discoverAllPackages(repoRoot: options.repoRoot);
  final packages = allPackages
      .where((final package) => package.isPublic)
      .toList(growable: false);
  final excludedPackageNames = allPackages
      .where((final package) => package.isPrivate)
      .map((final package) => package.name)
      .toSet();
  final existingPackages = options.existingIndexDirectory == null
      ? <String, Map<String, Object?>>{}
      : await loadExistingRegistryPackages(
          existingIndexDirectory: options.existingIndexDirectory!,
        );

  final outputDir = Directory(options.outputDirectory);
  await recreateDirectory(outputDir);

  final archivesDir = Directory('${outputDir.path}/archives');
  await archivesDir.create(recursive: true);

  final mergedPackages = <String, Map<String, Object?>>{
    for (final entry in existingPackages.entries)
      if (!excludedPackageNames.contains(entry.key)) entry.key: entry.value,
  };
  final manifestEntries = <Map<String, Object?>>[];
  final generatedAtUtc = DateTime.now().toUtc().toIso8601String();

  for (final package in packages) {
    stdout.writeln('Packaging ${package.name} ${package.version}');
    final archive = await createPackageArchive(
      package: package,
      outputDirectory: archivesDir.path,
    );
    final archiveSha = await computeSha256Hex(archive);

    final existingPayload = existingPackages[package.name];
    final publishedAt = _resolvePublishedAt(
      existingPayload: existingPayload,
      version: package.version,
      fallback:
          await gitLastCommitTimestamp(
            repoRoot: options.repoRoot,
            relativePath: package.relativePubspecPath,
          ) ??
          generatedAtUtc,
    );

    final nextVersion = <String, Object?>{
      'version': package.version,
      'archive_url': buildArchiveUrl(
        registryBaseUrl: options.registryBaseUrl,
        packageName: package.name,
        version: package.version,
      ),
      'archive_sha256': archiveSha,
      'pubspec': package.pubspecJson,
      'published': publishedAt,
    };

    final mergedVersions = _mergeVersions(
      existingVersions: _readVersions(existingPayload),
      newVersion: nextVersion,
    );

    mergedPackages[package.name] = <String, Object?>{
      'name': package.name,
      'latest': mergedVersions.last,
      'versions': mergedVersions,
    };

    manifestEntries.add(<String, Object?>{
      'name': package.name,
      'version': package.version,
      'release_tag': buildReleaseTag(
        packageName: package.name,
        version: package.version,
      ),
      'asset_name': buildArchiveAssetName(
        packageName: package.name,
        version: package.version,
      ),
      'archive_path': archive.path,
      'archive_sha256': archiveSha,
      'archive_url': buildArchiveUrl(
        registryBaseUrl: options.registryBaseUrl,
        packageName: package.name,
        version: package.version,
      ),
      if (options.githubRepository != null)
        'github_repository': options.githubRepository,
    });
  }

  for (final entry in mergedPackages.entries) {
    final payload = entry.value;
    final versions = _readVersions(payload);
    if (versions.isEmpty) {
      continue;
    }
    payload['latest'] = versions.last;
    payload['versions'] = versions;
  }

  final packageNames = mergedPackages.keys.toList(growable: false)..sort();

  final packagesDir = Directory('${outputDir.path}/api/packages');
  await packagesDir.create(recursive: true);

  for (final packageName in packageNames) {
    final outputFile = File('${packagesDir.path}/$packageName.json');
    final payload = mergedPackages[packageName]!;
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  final packageNamesFile = File('${outputDir.path}/api/package-names.json');
  await packageNamesFile.parent.create(recursive: true);
  await packageNamesFile.writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'packages': packageNames}),
  );

  manifestEntries.sort((final left, final right) {
    final leftName = left['name'] as String;
    final rightName = right['name'] as String;
    return leftName.compareTo(rightName);
  });

  final manifestFile = File('${outputDir.path}/release-manifest.json');
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'generated_at_utc': generatedAtUtc,
      'registry_base_url': options.registryBaseUrl,
      'excluded_private_packages': excludedPackageNames.toList()..sort(),
      if (options.githubRepository != null)
        'github_repository': options.githubRepository,
      'packages': manifestEntries,
    }),
  );

  stdout.writeln(
    'Registry index written to ${outputDir.path} '
    '(${manifestEntries.length} archive(s), ${packageNames.length} package(s)).',
  );
}

List<Map<String, Object?>> _readVersions(final Map<String, Object?>? payload) {
  if (payload == null) {
    return <Map<String, Object?>>[];
  }

  final rawVersions = payload['versions'];
  if (rawVersions is! List) {
    return <Map<String, Object?>>[];
  }

  final versions = rawVersions
      .whereType<Map>()
      .map(
        (final version) =>
            Map<String, Object?>.from(version.cast<String, Object?>()),
      )
      .toList(growable: false);

  versions.sort((final left, final right) {
    final leftVersion = SemanticVersion.parse(left['version'] as String);
    final rightVersion = SemanticVersion.parse(right['version'] as String);
    return leftVersion.compareTo(rightVersion);
  });
  return versions;
}

List<Map<String, Object?>> _mergeVersions({
  required final List<Map<String, Object?>> existingVersions,
  required final Map<String, Object?> newVersion,
}) {
  final byVersion = <String, Map<String, Object?>>{
    for (final version in existingVersions)
      version['version'] as String: version,
  };

  final versionKey = newVersion['version'] as String;
  final existing = byVersion[versionKey];
  if (existing != null && existing['published'] != null) {
    newVersion['published'] = existing['published'];
  }
  byVersion[versionKey] = newVersion;

  final merged = byVersion.values.toList(growable: false);
  merged.sort((final left, final right) {
    final leftVersion = SemanticVersion.parse(left['version'] as String);
    final rightVersion = SemanticVersion.parse(right['version'] as String);
    return leftVersion.compareTo(rightVersion);
  });
  return merged;
}

String _resolvePublishedAt({
  required final Map<String, Object?>? existingPayload,
  required final String version,
  required final String fallback,
}) {
  for (final existingVersion in _readVersions(existingPayload)) {
    if (existingVersion['version'] == version) {
      final published = existingVersion['published'];
      if (published is String && published.isNotEmpty) {
        return published;
      }
    }
  }
  return fallback;
}

class _BuildOptions {
  const _BuildOptions({
    required this.repoRoot,
    required this.outputDirectory,
    required this.registryBaseUrl,
    required this.existingIndexDirectory,
    required this.githubRepository,
  });

  final String repoRoot;
  final String outputDirectory;
  final String registryBaseUrl;
  final String? existingIndexDirectory;
  final String? githubRepository;

  static _BuildOptions parse(final List<String> args) {
    var repoRoot = Directory.current.path;
    var outputDirectory = '${Directory.current.path}/build/registry';
    var registryBaseUrl = 'https://pub.xsoulspace.dev';
    String? existingIndexDirectory;
    String? githubRepository = Platform.environment['GITHUB_REPOSITORY'];

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--repo-root':
          repoRoot = args[++index];
        case '--output-dir':
          outputDirectory = args[++index];
        case '--registry-base-url':
          registryBaseUrl = normalizeUrl(args[++index]);
        case '--existing-index-dir':
          existingIndexDirectory = args[++index];
        case '--github-repo':
          githubRepository = args[++index];
        default:
          stderr.writeln('Unknown argument: $arg');
          _printUsageAndExit();
      }
    }

    return _BuildOptions(
      repoRoot: repoRoot,
      outputDirectory: outputDirectory,
      registryBaseUrl: registryBaseUrl,
      existingIndexDirectory: existingIndexDirectory,
      githubRepository: githubRepository,
    );
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart registry/tools/build_registry_index.dart '
    '[--repo-root <path>] [--output-dir <path>] '
    '[--registry-base-url <url>] [--existing-index-dir <path>] '
    '[--github-repo <owner/repo>]',
  );
  exit(64);
}
