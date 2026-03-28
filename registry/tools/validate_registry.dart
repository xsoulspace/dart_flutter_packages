import 'dart:convert';
import 'dart:io';

import '_pubspec_rewriter.dart';
import '_registry_workspace.dart';

Future<void> main(final List<String> args) async {
  final options = _ValidateOptions.parse(args);
  final allPackages = await discoverAllPackages(repoRoot: options.repoRoot);
  final packages = allPackages
      .where((final package) => package.isPublic)
      .toList(growable: false);
  final packageMap = mapPackagesByName(packages);
  final internalNames = packageMap.keys.toSet();
  final privatePackageNames = allPackages
      .where((final package) => package.isPrivate)
      .map((final package) => package.name)
      .toSet();

  final issues = <String>[];
  final packageNamesFile = File(
    '${options.outputDirectory}/api/package-names.json',
  );
  final packageNamesPayload = await _readJsonObject(
    file: packageNamesFile,
    issues: issues,
    missingMessage: 'Missing ${packageNamesFile.path}',
  );

  final packageNames =
      (packageNamesPayload?['packages'] as List?)?.whereType<String>().toList(
        growable: false,
      ) ??
      <String>[];
  final sortedPackageNames = packageNames.toList(growable: false)..sort();
  final uniquePackageNames = sortedPackageNames.toSet();
  final expectedCurrentNames = packageMap.keys.toList(growable: false)..sort();

  if (packageNames.length != uniquePackageNames.length) {
    issues.add('api/package-names.json contains duplicate package names.');
  }
  if (packageNames.join('\n') != sortedPackageNames.join('\n')) {
    issues.add(
      'api/package-names.json must contain package names in sorted order.',
    );
  }
  for (final packageName in expectedCurrentNames) {
    if (!uniquePackageNames.contains(packageName)) {
      issues.add(
        'api/package-names.json is missing current package $packageName.',
      );
    }
  }
  for (final packageName in privatePackageNames) {
    if (uniquePackageNames.contains(packageName)) {
      issues.add(
        'api/package-names.json includes excluded private package $packageName.',
      );
    }
  }

  final packagesDir = Directory('${options.outputDirectory}/api/packages');
  final actualMetadataFiles = packagesDir.existsSync()
      ? (() {
          final files = packagesDir
              .listSync()
              .whereType<File>()
              .where((final file) => file.path.endsWith('.json'))
              .map((final file) => basename(file.path))
              .toList(growable: false);
          files.sort();
          return files;
        })()
      : <String>[];
  final expectedMetadataFiles =
      packageNames
          .map((final packageName) => '$packageName.json')
          .toList(growable: false)
        ..sort();
  if (actualMetadataFiles.join('\n') != expectedMetadataFiles.join('\n')) {
    issues.add(
      'api/packages contents do not exactly match api/package-names.json.',
    );
  }

  final archivesDir = Directory('${options.outputDirectory}/archives');
  final actualArchiveFiles = archivesDir.existsSync()
      ? (() {
          final files = archivesDir
              .listSync()
              .whereType<File>()
              .where((final file) => file.path.endsWith('.tar.gz'))
              .map((final file) => basename(file.path))
              .toList(growable: false);
          files.sort();
          return files;
        })()
      : <String>[];
  final expectedArchiveFiles = expectedArchiveFileNames(packages);
  if (actualArchiveFiles.join('\n') != expectedArchiveFiles.join('\n')) {
    issues.add(
      'archives contents do not exactly match current publishable package versions.',
    );
  }

  final manifestFile = File('${options.outputDirectory}/release-manifest.json');
  final manifestPayload = await _readJsonObject(
    file: manifestFile,
    issues: issues,
    missingMessage: 'Missing ${manifestFile.path}',
  );
  final manifestEntries =
      (manifestPayload?['packages'] as List?)
          ?.whereType<Map>()
          .map(
            (final entry) =>
                Map<String, Object?>.from(entry.cast<String, Object?>()),
          )
          .toList(growable: false) ??
      <Map<String, Object?>>[];
  final manifestNames =
      manifestEntries
          .map((final entry) => entry['name'])
          .whereType<String>()
          .toList(growable: false)
        ..sort();
  if (manifestNames.join('\n') != expectedCurrentNames.join('\n')) {
    issues.add(
      'release-manifest.json does not match current publishable package names.',
    );
  }
  final excludedManifestNames =
      (manifestPayload?['excluded_private_packages'] as List?)
          ?.whereType<String>()
          .toList(growable: false) ??
      <String>[];
  final sortedExcludedManifestNames = excludedManifestNames.toList(
    growable: false,
  )..sort();
  final expectedExcludedNames = privatePackageNames.toList(growable: false)
    ..sort();
  if (sortedExcludedManifestNames.join('\n') !=
      expectedExcludedNames.join('\n')) {
    issues.add(
      'release-manifest.json excluded_private_packages does not match private packages.',
    );
  }
  final manifestByName = {
    for (final entry in manifestEntries)
      if (entry['name'] is String) entry['name'] as String: entry,
  };

  for (final package in packages) {
    final dependencyIssues = validateHostedDependencies(
      content: package.pubspecContent,
      internalPackageNames: internalNames,
      hostedUrl: options.hostedUrl,
    );
    for (final dependencyIssue in dependencyIssues) {
      issues.add(
        '${package.relativePubspecPath}: ${dependencyIssue.section}:'
        '${dependencyIssue.packageName} ${dependencyIssue.reason}',
      );
    }

    final packageFile = File(
      '${options.outputDirectory}/api/packages/${package.name}.json',
    );
    final payload = await _readJsonObject(
      file: packageFile,
      issues: issues,
      missingMessage:
          'Missing metadata for ${package.name}: ${packageFile.path}',
    );
    if (payload == null) {
      continue;
    }

    if (payload['name'] != package.name) {
      issues.add('${packageFile.path} has incorrect package name.');
    }

    final versions = _readVersions(payload, packageFile.path, issues);
    if (versions.isEmpty) {
      continue;
    }

    final latest = payload['latest'];
    if (latest is! Map || latest['version'] != versions.last['version']) {
      issues.add(
        '${packageFile.path} has an incorrect latest version payload.',
      );
    }

    final currentVersion = versions.firstWhere(
      (final version) => version['version'] == package.version,
      orElse: () => <String, Object?>{},
    );
    if (currentVersion.isEmpty) {
      issues.add(
        '${packageFile.path} is missing current version ${package.version}.',
      );
      continue;
    }

    final expectedArchiveUrl = buildArchiveUrl(
      registryBaseUrl: options.registryBaseUrl,
      packageName: package.name,
      version: package.version,
    );
    if (currentVersion['archive_url'] != expectedArchiveUrl) {
      issues.add(
        '${packageFile.path} has archive_url ${currentVersion['archive_url']} '
        'but expected $expectedArchiveUrl.',
      );
    }

    final archiveFile = File(
      '${options.outputDirectory}/archives/'
      '${buildArchiveAssetName(packageName: package.name, version: package.version)}',
    );
    if (!archiveFile.existsSync()) {
      issues.add('Missing archive for ${package.name}: ${archiveFile.path}');
    } else {
      final archiveSha = await computeSha256Hex(archiveFile);
      if (currentVersion['archive_sha256'] != archiveSha) {
        issues.add(
          '${packageFile.path} has archive_sha256 ${currentVersion['archive_sha256']} '
          'but archive bytes hash to $archiveSha.',
        );
      }
    }

    final metadataPubspec = currentVersion['pubspec'];
    if (jsonEncode(metadataPubspec) != jsonEncode(package.pubspecJson)) {
      issues.add(
        '${packageFile.path} pubspec payload does not match pubspec.yaml.',
      );
    }

    final manifestEntry = manifestByName[package.name];
    if (manifestEntry == null) {
      issues.add('release-manifest.json is missing ${package.name}.');
      continue;
    }

    if (manifestEntry['version'] != package.version) {
      issues.add(
        'release-manifest.json has version ${manifestEntry['version']} '
        'for ${package.name}, expected ${package.version}.',
      );
    }
    if (manifestEntry['archive_url'] != expectedArchiveUrl) {
      issues.add(
        'release-manifest.json has archive_url ${manifestEntry['archive_url']} '
        'for ${package.name}, expected $expectedArchiveUrl.',
      );
    }
    if (manifestEntry['archive_sha256'] != currentVersion['archive_sha256']) {
      issues.add(
        'release-manifest.json has archive_sha256 ${manifestEntry['archive_sha256']} '
        'for ${package.name}, expected ${currentVersion['archive_sha256']}.',
      );
    }
  }

  for (final privatePackageName in privatePackageNames) {
    final privateMetadataFile = File(
      '${options.outputDirectory}/api/packages/$privatePackageName.json',
    );
    if (privateMetadataFile.existsSync()) {
      issues.add(
        'Excluded private package is present: ${privateMetadataFile.path}',
      );
    }
  }

  if (issues.isNotEmpty) {
    for (final issue in issues) {
      stderr.writeln('ERROR: $issue');
    }
    exit(1);
  }

  stdout.writeln(
    'Registry metadata validated for ${packages.length} publishable package(s).',
  );
}

Future<Map<String, Object?>?> _readJsonObject({
  required final File file,
  required final List<String> issues,
  required final String missingMessage,
}) async {
  if (!file.existsSync()) {
    issues.add(missingMessage);
    return null;
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    issues.add('${file.path} is not a JSON object.');
    return null;
  }

  return Map<String, Object?>.from(decoded.cast<String, Object?>());
}

List<Map<String, Object?>> _readVersions(
  final Map<String, Object?> payload,
  final String filePath,
  final List<String> issues,
) {
  final rawVersions = payload['versions'];
  if (rawVersions is! List) {
    issues.add('$filePath does not contain a versions array.');
    return <Map<String, Object?>>[];
  }

  final versions = rawVersions
      .whereType<Map>()
      .map(
        (final entry) =>
            Map<String, Object?>.from(entry.cast<String, Object?>()),
      )
      .toList(growable: false);
  if (versions.isEmpty) {
    issues.add('$filePath does not contain any versions.');
    return <Map<String, Object?>>[];
  }

  versions.sort((final left, final right) {
    final leftVersion = SemanticVersion.parse(left['version'] as String);
    final rightVersion = SemanticVersion.parse(right['version'] as String);
    return leftVersion.compareTo(rightVersion);
  });
  return versions;
}

class _ValidateOptions {
  const _ValidateOptions({
    required this.repoRoot,
    required this.outputDirectory,
    required this.registryBaseUrl,
    required this.hostedUrl,
  });

  final String repoRoot;
  final String outputDirectory;
  final String registryBaseUrl;
  final String hostedUrl;

  static _ValidateOptions parse(final List<String> args) {
    var repoRoot = Directory.current.path;
    var outputDirectory = '${Directory.current.path}/build/registry';
    var registryBaseUrl = 'https://pub.xsoulspace.dev';
    var hostedUrl = 'https://pub.xsoulspace.dev';

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--repo-root':
          repoRoot = args[++index];
        case '--output-dir':
          outputDirectory = args[++index];
        case '--registry-base-url':
          registryBaseUrl = normalizeUrl(args[++index]);
        case '--hosted-url':
          hostedUrl = normalizeUrl(args[++index]);
        default:
          stderr.writeln('Unknown argument: $arg');
          _printUsageAndExit();
      }
    }

    return _ValidateOptions(
      repoRoot: repoRoot,
      outputDirectory: outputDirectory,
      registryBaseUrl: registryBaseUrl,
      hostedUrl: hostedUrl,
    );
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart registry/tools/validate_registry.dart '
    '[--repo-root <path>] [--output-dir <path>] '
    '[--registry-base-url <url>] [--hosted-url <url>]',
  );
  exit(64);
}
