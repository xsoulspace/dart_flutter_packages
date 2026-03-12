import 'dart:io';

/// Updates `version:` in `pkgs/<package>/pubspec.yaml` to the given version.
Future<void> main(final List<String> args) async {
  final options = _BumpOptions.parse(args);
  final pubspecPath = '${options.repoRoot}/pkgs/${options.packageName}/pubspec.yaml';
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    stderr.writeln('No such package: ${options.packageName} (missing $pubspecPath)');
    exit(1);
  }

  final content = await file.readAsString();
  final versionRe = RegExp(r'^(version:\s*)(["\x27]?[\w.+-]+["\x27]?)', multiLine: true);
  if (!versionRe.hasMatch(content)) {
    stderr.writeln('No version: line found in $pubspecPath');
    exit(1);
  }

  final prefix = versionRe.firstMatch(content)!.group(1)!;
  final newContent = content.replaceFirst(versionRe, '$prefix${options.version}');
  if (newContent == content) {
    stderr.writeln('Version unchanged.');
    exit(0);
  }

  await file.writeAsString(newContent);
  stdout.writeln('Updated ${options.packageName} to ${options.version}');
}

class _BumpOptions {
  const _BumpOptions({
    required this.repoRoot,
    required this.packageName,
    required this.version,
  });

  final String repoRoot;
  final String packageName;
  final String version;

  static _BumpOptions parse(final List<String> args) {
    if (args.length < 2) _printUsageAndExit();
    var repoRoot = Directory.current.path;
    var i = 0;
    while (i < args.length - 2) {
      if (args[i] == '--repo-root' && i + 1 < args.length) {
        repoRoot = args[++i];
        i++;
        continue;
      }
      i++;
    }
    final packageName = args[args.length - 2];
    final version = args[args.length - 1];
    if (packageName.isEmpty || version.isEmpty) _printUsageAndExit();
    return _BumpOptions(repoRoot: repoRoot, packageName: packageName, version: version);
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart registry/tools/registry_bump.dart [--repo-root <path>] <package> <version>',
  );
  exit(64);
}
