import 'dart:io';

import 'package:yaml/yaml.dart';

/// Repository-level configuration, loaded from `changesets.yaml` at the repo
/// root. Every key is optional; absent files use the defaults below.
final class ChangesetsConfig {
  const ChangesetsConfig({
    this.packagesDir = 'pkgs',
    this.dependentBump = DependentBump.patch,
    this.ignore = const <String>{},
    this.tagFormat = '{package}-v{version}',
  });

  /// Directory scanned one level deep for package `pubspec.yaml` files.
  final String packagesDir;

  /// Version bump applied to publishable dependents whose dependency
  /// constraint had to be rewritten during a cascade.
  final DependentBump dependentBump;

  /// Packages this tool must never release (in addition to any package whose
  /// pubspec declares `publish_to: none`, which is always private).
  final Set<String> ignore;

  /// Tag template with `{package}` and `{version}` placeholders. The default
  /// matches pub.dev's per-package automated-publishing tag patterns.
  final String tagFormat;

  /// Formats the release tag for [package] at [version].
  String tagFor(String package, String version) => tagFormat
      .replaceAll('{package}', package)
      .replaceAll('{version}', version);

  /// Parses a release tag previously produced by [tagFor]. Returns
  /// `(package, version)` or `null` when the tag does not match the format.
  (String, String)? parseTag(String tag) {
    final packagePlaceholder = tagFormat.indexOf('{package}');
    final versionPlaceholder = tagFormat.indexOf('{version}');
    if (packagePlaceholder < 0 || versionPlaceholder < 0) {
      return null;
    }
    // Split around the placeholders; the literal segments must appear in
    // order with arbitrary package/version values between them.
    final beforePackage = tagFormat.substring(0, packagePlaceholder);
    final between = tagFormat.substring(
      packagePlaceholder + '{package}'.length,
      versionPlaceholder,
    );
    final afterVersion = tagFormat.substring(
      versionPlaceholder + '{version}'.length,
    );
    var rest = tag;
    if (beforePackage.isNotEmpty) {
      if (!rest.startsWith(beforePackage)) return null;
      rest = rest.substring(beforePackage.length);
    }
    if (afterVersion.isNotEmpty) {
      if (!rest.endsWith(afterVersion)) return null;
      rest = rest.substring(0, rest.length - afterVersion.length);
    }
    if (between.isEmpty) return null;
    final betweenIndex = rest.lastIndexOf(between);
    if (betweenIndex < 0) return null;
    final package = rest.substring(0, betweenIndex);
    final version = rest.substring(betweenIndex + between.length);
    if (package.isEmpty || version.isEmpty) return null;
    return (package, version);
  }

  static ChangesetsConfig loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const ChangesetsConfig();
    }
    final doc = loadYamlNode(file.readAsStringSync());
    if (doc is! YamlMap) {
      throw FormatException('changesets.yaml must be a YAML mapping: $path');
    }
    return ChangesetsConfig(
      packagesDir: (doc['packages_dir'] as String?) ?? 'pkgs',
      dependentBump: DependentBump.fromString(
        (doc['dependent_bump'] as String?) ?? 'patch',
      ),
      ignore: {
        if (doc['ignore'] is YamlList)
          for (final entry in doc['ignore'] as YamlList) entry.toString(),
      },
      tagFormat: (doc['tag_format'] as String?) ?? '{package}-v{version}',
    );
  }
}

/// How much to bump a publishable dependent whose dependency constraint was
/// rewritten during a cascade.
enum DependentBump {
  patch,
  minor;

  static DependentBump fromString(String value) => switch (value) {
        'patch' => DependentBump.patch,
        'minor' => DependentBump.minor,
        _ => throw FormatException(
            'changesets.yaml: dependent_bump must be "patch" or "minor", '
            'got "$value"',
          ),
      };

  String get asString => name;
}
