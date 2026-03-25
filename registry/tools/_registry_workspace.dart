import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

class PackageInfo {
  const PackageInfo({
    required this.name,
    required this.version,
    required this.directoryPath,
    required this.relativeDirectory,
    required this.relativePubspecPath,
    required this.pubspecPath,
    required this.pubspecContent,
    required this.pubspecJson,
    required this.publishTo,
  });

  final String name;
  final String version;
  final String directoryPath;
  final String relativeDirectory;
  final String relativePubspecPath;
  final String pubspecPath;
  final String pubspecContent;
  final Map<String, Object?> pubspecJson;
  final String? publishTo;

  bool get isPrivate => publishTo == 'none';
  bool get isPublic => !isPrivate;
}

Future<List<PackageInfo>> discoverPackages({
  required final String repoRoot,
  final bool includePrivate = true,
}) async {
  final pkgsDir = Directory('$repoRoot/pkgs');
  if (!pkgsDir.existsSync()) {
    throw StateError('pkgs directory not found at $repoRoot');
  }

  final packages = <PackageInfo>[];
  final directories = pkgsDir.listSync().whereType<Directory>().toList(
    growable: false,
  )..sort((final a, final b) => a.path.compareTo(b.path));

  for (final directory in directories) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      continue;
    }

    final content = await pubspec.readAsString();
    final document = _parsePubspec(content);
    if (document is! Map) {
      throw FormatException(
        'pubspec.yaml is not a YAML mapping: ${pubspec.path}',
      );
    }

    final pubspecJson = Map<String, Object?>.from(
      document.cast<String, Object?>(),
    );
    final name = pubspecJson['name'];
    final version = pubspecJson['version'];

    if (name is! String || name.isEmpty) {
      throw FormatException('Missing package name in ${pubspec.path}');
    }
    if (version is! String || version.isEmpty) {
      throw FormatException('Missing package version in ${pubspec.path}');
    }

    final relativeDirectory = 'pkgs/${basename(directory.path)}';
    final package = PackageInfo(
      name: name,
      version: version,
      directoryPath: directory.path,
      relativeDirectory: relativeDirectory,
      relativePubspecPath: '$relativeDirectory/pubspec.yaml',
      pubspecPath: pubspec.path,
      pubspecContent: content,
      pubspecJson: pubspecJson,
      publishTo: pubspecJson['publish_to'] as String?,
    );

    if (includePrivate || package.isPublic) {
      packages.add(package);
    }
  }

  return packages;
}

Future<List<PackageInfo>> discoverAllPackages({
  required final String repoRoot,
}) {
  return discoverPackages(repoRoot: repoRoot, includePrivate: true);
}

Object? _parsePubspec(final String content) {
  final document = loadYaml(content);
  return _normalizeYamlValue(document);
}

Object? _normalizeYamlValue(final Object? value) {
  if (value is YamlMap) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        throw FormatException('pubspec.yaml contains a non-string map key.');
      }
      result[key] = _normalizeYamlValue(entry.value);
    }
    return result;
  }

  if (value is YamlList) {
    return value
        .map(_normalizeYamlValue)
        .toList(growable: false);
  }

  if (value is num || value is String || value is bool || value == null) {
    return value;
  }

  return value.toString();
}

Map<String, PackageInfo> mapPackagesByName(
  final Iterable<PackageInfo> packages,
) {
  return {for (final package in packages) package.name: package};
}

Set<String> packageNameSet(final Iterable<PackageInfo> packages) {
  return packages.map((final package) => package.name).toSet();
}

List<String> expectedArchiveFileNames(final Iterable<PackageInfo> packages) {
  return packages
      .map(
        (final package) => buildArchiveAssetName(
          packageName: package.name,
          version: package.version,
        ),
      )
      .toList(growable: false)
    ..sort();
}

List<String> expectedMetadataFileNames(final Iterable<PackageInfo> packages) {
  return packages
      .map((final package) => '${package.name}.json')
      .toList(growable: false)
    ..sort();
}

String normalizeUrl(final String url) {
  return url.replaceFirst(RegExp(r'/+$'), '');
}

String buildArchiveUrl({
  required final String registryBaseUrl,
  required final String packageName,
  required final String version,
}) {
  final baseUrl = normalizeUrl(registryBaseUrl);
  return '$baseUrl/packages/$packageName/versions/$version.tar.gz';
}

String buildReleaseTag({
  required final String packageName,
  required final String version,
}) {
  return '$packageName-v$version';
}

String buildArchiveAssetName({
  required final String packageName,
  required final String version,
}) {
  return '$packageName-$version.tar.gz';
}

Future<void> recreateDirectory(final Directory directory) async {
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
  await directory.create(recursive: true);
}

Future<List<String>> listTrackedPackageFiles({
  required final PackageInfo package,
}) async {
  try {
    final result = await Process.run('git', <String>[
      '-C',
      package.directoryPath,
      'ls-files',
    ]);

    if (result.exitCode == 0) {
      final files = LineSplitter.split(result.stdout.toString())
          .map((final line) => line.trim())
          .where((final line) => line.isNotEmpty)
          .where((final line) => line != 'pubspec_overrides.yaml')
          .toList(growable: false);

      if (files.isNotEmpty) {
        return files..sort();
      }
    }
  } on ProcessException {
    // Fall back to a filesystem walk when git metadata is unavailable.
  }

  return Directory(package.directoryPath)
      .listSync(recursive: true)
      .whereType<File>()
      .where((final file) {
        final relative = file.path.substring(package.directoryPath.length + 1);
        if (relative == 'pubspec_overrides.yaml') {
          return false;
        }
        if (relative.startsWith('.dart_tool/')) {
          return false;
        }
        if (relative.startsWith('build/')) {
          return false;
        }
        return true;
      })
      .map(
        (final file) => file.path.substring(package.directoryPath.length + 1),
      )
      .toList(growable: false)
    ..sort();
}

Future<File> createPackageArchive({
  required final PackageInfo package,
  required final String outputDirectory,
}) async {
  final files = await listTrackedPackageFiles(package: package);
  if (files.isEmpty) {
    throw StateError('No package files found for ${package.name}');
  }

  final outputDir = Directory(outputDirectory);
  await outputDir.create(recursive: true);

  final archiveName = buildArchiveAssetName(
    packageName: package.name,
    version: package.version,
  );
  final archiveFile = File('${outputDir.path}/$archiveName');
  if (archiveFile.existsSync()) {
    archiveFile.deleteSync();
  }

  final tempDir = await Directory.systemTemp.createTemp(
    'xs-registry-archive-',
  );
  final manifestFile = File('${tempDir.path}/files.json');
  await manifestFile.writeAsString(jsonEncode(files));

  try {
    final result = await Process.run('python3', <String>[
      'registry/tools/_build_deterministic_archive.py',
      '--package-dir',
      package.directoryPath,
      '--output',
      archiveFile.path,
      '--manifest',
      manifestFile.path,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'python3',
        <String>[
          'registry/tools/_build_deterministic_archive.py',
          '--package-dir',
          package.directoryPath,
          '--output',
          archiveFile.path,
          '--manifest',
          manifestFile.path,
        ],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }

  return archiveFile;
}

Future<String> computeSha256Hex(final File file) async {
  final candidates = <List<String>>[
    <String>['shasum', '-a', '256', file.path],
    <String>['sha256sum', file.path],
    <String>['openssl', 'dgst', '-sha256', file.path],
  ];

  for (final candidate in candidates) {
    try {
      final result = await Process.run(candidate.first, candidate.sublist(1));
      if (result.exitCode != 0) {
        continue;
      }

      final output = result.stdout.toString().trim();
      final hashMatch = RegExp(r'([a-fA-F0-9]{64})').firstMatch(output);
      if (hashMatch != null) {
        return hashMatch.group(1)!.toLowerCase();
      }
    } on ProcessException {
      continue;
    }
  }

  throw StateError('Unable to compute SHA256 for ${file.path}');
}

Future<String?> gitLastCommitTimestamp({
  required final String repoRoot,
  required final String relativePath,
}) async {
  final result = await Process.run('git', <String>[
    '-C',
    repoRoot,
    'log',
    '-1',
    '--format=%cI',
    '--',
    relativePath,
  ]);

  if (result.exitCode != 0) {
    return null;
  }

  final output = result.stdout.toString().trim();
  if (output.isEmpty) {
    return null;
  }
  return output;
}

Future<Map<String, Map<String, Object?>>> loadExistingRegistryPackages({
  required final String existingIndexDirectory,
}) async {
  final packagesDir = Directory('$existingIndexDirectory/api/packages');
  if (!packagesDir.existsSync()) {
    return <String, Map<String, Object?>>{};
  }

  final result = <String, Map<String, Object?>>{};
  final files =
      packagesDir
          .listSync()
          .whereType<File>()
          .where((final file) => file.path.endsWith('.json'))
          .toList(growable: false)
        ..sort((final a, final b) => a.path.compareTo(b.path));

  for (final file in files) {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      continue;
    }
    final payload = Map<String, Object?>.from(decoded.cast<String, Object?>());
    final packageName = payload['name'];
    if (packageName is String && packageName.isNotEmpty) {
      result[packageName] = payload;
    }
  }

  return result;
}

String basename(final String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? path : segments.last;
}

class SemanticVersion implements Comparable<SemanticVersion> {
  SemanticVersion.parse(final String version)
    : original = version,
      buildMetadata = _extractBuild(version),
      _coreAndPrerelease = _stripBuild(version) {
    final prereleaseSeparator = _coreAndPrerelease.indexOf('-');
    final pieces = prereleaseSeparator == -1
        ? <String>[_coreAndPrerelease]
        : <String>[
            _coreAndPrerelease.substring(0, prereleaseSeparator),
            _coreAndPrerelease.substring(prereleaseSeparator + 1),
          ];
    final core = pieces.first.split('.');
    if (core.length != 3) {
      throw FormatException('Unsupported semantic version: $version');
    }
    major = int.parse(core[0]);
    minor = int.parse(core[1]);
    patch = int.parse(core[2]);
    prerelease = pieces.length == 1 ? <String>[] : pieces[1].split('.');
  }

  final String original;
  final String? buildMetadata;
  final String _coreAndPrerelease;
  late final int major;
  late final int minor;
  late final int patch;
  late final List<String> prerelease;

  static String _stripBuild(final String value) => value.split('+').first;

  static String? _extractBuild(final String value) {
    final parts = value.split('+');
    return parts.length > 1 ? parts.sublist(1).join('+') : null;
  }

  @override
  int compareTo(final SemanticVersion other) {
    final coreComparison =
        _compareInts(major, other.major) ??
        _compareInts(minor, other.minor) ??
        _compareInts(patch, other.patch);
    if (coreComparison != null) {
      return coreComparison;
    }

    if (prerelease.isEmpty && other.prerelease.isEmpty) {
      return 0;
    }
    if (prerelease.isEmpty) {
      return 1;
    }
    if (other.prerelease.isEmpty) {
      return -1;
    }

    final maxLength = prerelease.length > other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var i = 0; i < maxLength; i += 1) {
      if (i >= prerelease.length) {
        return -1;
      }
      if (i >= other.prerelease.length) {
        return 1;
      }

      final comparison = _comparePrereleasePart(
        prerelease[i],
        other.prerelease[i],
      );
      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  static int? _compareInts(final int left, final int right) {
    if (left == right) {
      return null;
    }
    return left < right ? -1 : 1;
  }

  static int _comparePrereleasePart(final String left, final String right) {
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    if (leftNumber != null) {
      return -1;
    }
    if (rightNumber != null) {
      return 1;
    }
    return left.compareTo(right);
  }

  @override
  String toString() => original;
}
