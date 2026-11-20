import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'config.dart';

/// One package discovered under the configured packages directory.
final class WorkspacePackage {
  WorkspacePackage({
    required this.name,
    required this.version,
    required this.pubspecPath,
    required this.pubspecContent,
    required this.publishable,
    required this.dependencies,
    required this.devDependencies,
    required this.sdkConstraint,
  });

  final String name;
  final Version version;
  final String pubspecPath;

  /// Raw pubspec text — the surgical-edit source for version and constraint
  /// rewrites (comments and formatting are preserved).
  final String pubspecContent;

  /// `false` when the pubspec declares `publish_to: none`.
  final bool publishable;

  /// Regular dependencies: package name → raw constraint (or form marker).
  final Map<String, DependencyRef> dependencies;
  final Map<String, DependencyRef> devDependencies;

  final String? sdkConstraint;

  /// Whether this package runs on Flutter (needs `flutter pub publish`).
  bool get isFlutter =>
      dependencies.containsKey('flutter') && dependencies['flutter']!.isSdk;

  /// All internal (workspace) references to [name], in regular deps.
  bool dependsOn(String name) =>
      dependencies.containsKey(name) || devDependencies.containsKey(name);

  DependencyRef? dependencyOn(String name) =>
      dependencies[name] ?? devDependencies[name];

  String get directory => p.dirname(pubspecPath);
}

/// How a pubspec references a dependency, plus its version constraint when
/// one exists.
final class DependencyRef {
  const DependencyRef._({
    required this.kind,
    this.constraint,
    this.path,
    this.hostedUrl,
  });

  /// Plain hosted constraint: `name: ^1.2.3`.
  factory DependencyRef.hosted(String constraint) =>
      DependencyRef._(kind: DependencyKind.hosted, constraint: constraint);

  /// Explicit hosted-url block:
  /// `name: {hosted: {name: …, url: …}, version: ^1.2.3}`.
  factory DependencyRef.hostedUrl(String constraint, String url) =>
      DependencyRef._(
        kind: DependencyKind.hostedUrl,
        constraint: constraint,
        hostedUrl: url,
      );

  /// SDK dependency: `name: {sdk: flutter}`.
  factory DependencyRef.sdk() => const DependencyRef._(kind: DependencyKind.sdk);

  /// Path dependency: `name: {path: ../x}`.
  factory DependencyRef.path(String path) =>
      DependencyRef._(kind: DependencyKind.path, path: path);

  /// Git dependency.
  factory DependencyRef.git() => const DependencyRef._(kind: DependencyKind.git);

  final DependencyKind kind;

  /// Raw constraint string (`^1.2.3`), or `null` for sdk/path/git forms.
  final String? constraint;
  final String? path;
  final String? hostedUrl;

  bool get isSdk => kind == DependencyKind.sdk;
  bool get isPath => kind == DependencyKind.path;
  bool get isHosted =>
      kind == DependencyKind.hosted || kind == DependencyKind.hostedUrl;
}

enum DependencyKind { hosted, hostedUrl, sdk, path, git }

/// The package graph of the repository: every package under
/// [ChangesetsConfig.packagesDir], its classification, and its internal
/// references.
final class WorkspaceGraph {
  WorkspaceGraph._(this.packages);

  final Map<String, WorkspacePackage> packages;

  static Future<WorkspaceGraph> load(
    String repoRoot,
    ChangesetsConfig config,
  ) async {
    final dir = Directory(p.join(repoRoot, config.packagesDir));
    if (!dir.existsSync()) {
      throw StateError(
        'packages directory not found: ${dir.path} '
        '(configure packages_dir in changesets.yaml)',
      );
    }
    final found = <String, WorkspacePackage>{};
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final pubspecFile = File(p.join(entry.path, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) continue;
      final content = pubspecFile.readAsStringSync();
      final doc = loadYamlNode(content);
      if (doc is! YamlMap) continue;
      final name = doc['name']?.toString();
      final versionRaw = doc['version']?.toString();
      if (name == null || versionRaw == null) continue;

      final publishTo = doc['publish_to'];
      final publishable = publishTo == null || publishTo.toString() != 'none';

      final pkg = WorkspacePackage(
        name: name,
        version: Version.parse(versionRaw),
        pubspecPath: pubspecFile.path,
        pubspecContent: content,
        publishable: publishable,
        dependencies: _readDependencies(doc['dependencies']),
        devDependencies: _readDependencies(doc['dev_dependencies']),
        sdkConstraint: doc['environment'] is YamlMap
            ? (doc['environment'] as YamlMap)['sdk']?.toString()
            : null,
      );
      found[pkg.name] = pkg;
    }
    return WorkspaceGraph._(Map.unmodifiable(found));
  }

  /// Packages that reference [name] (regular or dev dependencies).
  List<WorkspacePackage> reverseDependents(String name) => packages.values
      .where((pkg) => pkg.name != name && pkg.dependsOn(name))
      .toList(growable: false);

  /// Publishable packages only, sorted by name.
  List<WorkspacePackage> get publishable =>
      packages.values.where((pkg) => pkg.publishable).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
}

Map<String, DependencyRef> _readDependencies(Object? node) {
  if (node is! YamlMap) return const <String, DependencyRef>{};
  final result = <String, DependencyRef>{};
  for (final entry in node.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (value is String) {
      result[name] = DependencyRef.hosted(value);
      continue;
    }
    if (value is! YamlMap) continue;
    final sdk = value['sdk'];
    if (sdk != null) {
      result[name] = DependencyRef.sdk();
      continue;
    }
    final path = value['path'];
    if (path != null) {
      result[name] = DependencyRef.path(path.toString());
      continue;
    }
    if (value.containsKey('git')) {
      result[name] = DependencyRef.git();
      continue;
    }
    final hosted = value['hosted'];
    final version = value['version']?.toString();
    if (hosted is YamlMap && version != null) {
      result[name] = DependencyRef.hostedUrl(
        version,
        hosted['url']?.toString() ?? '',
      );
      continue;
    }
    if (version != null) {
      result[name] = DependencyRef.hosted(version);
    }
  }
  return result;
}

/// Rewrites the version constraint of [depName] inside [pubspecContent],
/// preserving comments and formatting. Handles both plain form
/// (`name: ^1.2.3`) and nested form (`name:\n  version: ^1.2.3`).
///
/// Returns the new content, or `null` when no constraint line was found.
String? rewriteConstraint(
  String pubspecContent,
  String depName,
  String newConstraint,
) {
  final escaped = RegExp.escape(depName);
  // Plain scalar form — a colon followed by an inline value on one line.
  final plain = RegExp(
    r'^([ \t]*)' + escaped + r':([ \t]+)([^#\s][^\s#]*)(\s*(?:#.*)?)$',
    multiLine: true,
  );
  final plainMatch = plain.firstMatch(pubspecContent);
  if (plainMatch != null) {
    return pubspecContent.replaceRange(
      plainMatch.start,
      plainMatch.end,
      '${plainMatch.group(1)}$depName:${plainMatch.group(2)}'
      '$newConstraint${plainMatch.group(4)}',
    );
  }

  // Nested form — the dependency name opens a block; find its `version:`
  // key before the next sibling key (a line with indentation <= the dep's).
  final blockStart = RegExp(
    r'^([ \t]*)' + escaped + r':[ \t]*$',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (blockStart == null) return null;
  final depIndent = blockStart.group(1)!.length;
  var searchIndex = blockStart.end;
  while (true) {
    final lineEnd = pubspecContent.indexOf('\n', searchIndex);
    if (lineEnd < 0) break;
    final lineStart = searchIndex;
    searchIndex = lineEnd + 1;
    final line = pubspecContent.substring(lineStart, lineEnd);
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= depIndent) break; // left the dependency block
    final versionMatch = RegExp(
      r'^([ \t]+version:[ \t]+)([^#\s][^\s#]*)(\s*(?:#.*)?)$',
      multiLine: true,
    ).firstMatch(line);
    if (versionMatch != null) {
      final absoluteStart = lineStart + versionMatch.start;
      final absoluteEnd = lineStart + versionMatch.end;
      return pubspecContent.replaceRange(
        absoluteStart,
        absoluteEnd,
        '${versionMatch.group(1)}$newConstraint${versionMatch.group(3)}',
      );
    }
  }
  return null;
}

/// Rewrites the `version:` line of a pubspec, preserving surrounding text.
String rewriteVersion(String pubspecContent, Version newVersion) {
  final match = RegExp(
    r'^(version:[ \t]+)([^#\s][^\s#]*)(\s*(?:#.*)?)$',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (match == null) {
    throw StateError('pubspec has no version: line');
  }
  return pubspecContent.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}${newVersion.canonicalizedVersion}${match.group(3)}',
  );
}
