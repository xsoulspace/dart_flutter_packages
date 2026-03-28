import 'dart:io';

import '_registry_workspace.dart';

/// Adds (or updates) a hosted internal dependency to a package's pubspec.yaml.
Future<void> main(final List<String> args) async {
  final options = _AddOptions.parse(args);
  final pubspecPath =
      '${options.repoRoot}/pkgs/${options.targetPackage}/pubspec.yaml';
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    stderr.writeln(
      'No such package: ${options.targetPackage} (missing $pubspecPath)',
    );
    exit(1);
  }

  final packages = await discoverPackages(
    repoRoot: options.repoRoot,
    includePrivate: false,
  );
  final internalNames = packages.map((final p) => p.name).toSet();
  if (!internalNames.contains(options.dependencyPackage)) {
    stderr.writeln(
      '${options.dependencyPackage} is not a public package in this repo. '
      'Use registry-add only for internal packages.',
    );
    exit(1);
  }

  final content = await file.readAsString();
  final block = _hostedBlock(
    packageName: options.dependencyPackage,
    hostedUrl: options.hostedUrl,
    version: options.version,
  );

  final result = _insertOrUpdateHostedDependency(
    content: content,
    section: 'dependencies',
    packageName: options.dependencyPackage,
    block: block,
  );

  if (result == null) {
    stderr.writeln('Could not find dependencies: section in $pubspecPath');
    exit(1);
  }

  if (result == content) {
    stdout.writeln(
      '${options.dependencyPackage} already present with requested version.',
    );
    return;
  }

  await file.writeAsString(result);
  stdout.writeln(
    'Added ${options.dependencyPackage} ${options.version} to ${options.targetPackage}. '
    'Run just registry-rewrite-hosted to normalize internal deps.',
  );
}

String _hostedBlock({
  required final String packageName,
  required final String hostedUrl,
  required final String version,
}) {
  final url = normalizeUrl(hostedUrl);
  return '''
  $packageName:
    hosted:
      name: $packageName
      url: $url
    version: $version''';
}

/// Returns new content, or null if section not found, or same content if no change.
String? _insertOrUpdateHostedDependency({
  required final String content,
  required final String section,
  required final String packageName,
  required final String block,
}) {
  final lines = content.split('\n');
  final sectionHeader = '$section:';
  var sectionStart = -1;
  var sectionEnd = lines.length;
  var existingStart = -1;
  var existingEnd = -1;

  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed == sectionHeader && _indentOf(lines[i]) == 0) {
      sectionStart = i;
      continue;
    }
    if (sectionStart >= 0 &&
        _indentOf(lines[i]) == 0 &&
        trimmed.endsWith(':')) {
      sectionEnd = i;
      break;
    }
    if (sectionStart >= 0 &&
        i > sectionStart &&
        _indentOf(lines[i]) == 2 &&
        trimmed.startsWith('$packageName:')) {
      existingStart = i;
      var j = i + 1;
      while (j < lines.length &&
          (_indentOf(lines[j]) > 2 || lines[j].trim().isEmpty)) {
        j++;
      }
      existingEnd = j;
      break;
    }
  }

  if (sectionStart < 0) return null;

  final blockLines = block
      .split('\n')
      .where((final l) => l.isNotEmpty)
      .toList(growable: false);

  if (existingStart >= 0) {
    final before = lines.sublist(0, existingStart);
    final after = lines.sublist(existingEnd);
    final newContent = [...before, ...blockLines, ...after].join('\n');
    return _preserveTrailingNewline(content, newContent);
  }

  var insertAt = sectionStart + 1;
  while (insertAt < sectionEnd &&
      (_indentOf(lines[insertAt]) > 2 || lines[insertAt].trim().isEmpty)) {
    insertAt++;
  }
  final before = lines.sublist(0, insertAt);
  final after = lines.sublist(insertAt);
  final newContent = [...before, ...blockLines, ...after].join('\n');
  return _preserveTrailingNewline(content, newContent);
}

int _indentOf(final String line) {
  var i = 0;
  while (i < line.length && (line[i] == ' ' || line[i] == '\t')) i++;
  return i;
}

String _preserveTrailingNewline(final String original, final String updated) {
  if (original.endsWith('\n') && !updated.endsWith('\n')) return '$updated\n';
  if (!original.endsWith('\n') && updated.endsWith('\n')) {
    return updated.substring(0, updated.length - 1);
  }
  return updated;
}

class _AddOptions {
  const _AddOptions({
    required this.repoRoot,
    required this.hostedUrl,
    required this.targetPackage,
    required this.dependencyPackage,
    required this.version,
  });

  final String repoRoot;
  final String hostedUrl;
  final String targetPackage;
  final String dependencyPackage;
  final String version;

  static _AddOptions parse(final List<String> args) {
    final positional = <String>[];
    var repoRoot = Directory.current.path;
    var hostedUrl = 'https://pub.xsoulspace.dev';

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--repo-root':
          if (i + 1 < args.length) repoRoot = args[++i];
          break;
        case '--hosted-url':
          if (i + 1 < args.length) hostedUrl = args[++i];
          break;
        default:
          if (!args[i].startsWith('--')) positional.add(args[i]);
      }
    }

    if (positional.length < 2) _printUsageAndExit();
    final targetPackage = positional[0];
    final dependencyPackage = positional[1];
    final version = positional.length >= 3 ? positional[2] : '^0.0.0';

    return _AddOptions(
      repoRoot: repoRoot,
      hostedUrl: hostedUrl,
      targetPackage: targetPackage,
      dependencyPackage: dependencyPackage,
      version: version,
    );
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart registry/tools/registry_add.dart '
    '[--repo-root <path>] [--hosted-url <url>] <target_package> <dependency_package> [version]',
  );
  exit(64);
}
