import 'dart:convert';
import 'dart:io';

/// Reads [release-manifest.json] from the registry build output and prints
/// a one-line summary of what would be published (package name + version).
Future<void> main(final List<String> args) async {
  final options = _PreviewOptions.parse(args);
  final manifestFile = File('${options.outputDirectory}/release-manifest.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln(
      'Release manifest not found: ${manifestFile.path}. '
      'Run registry-build-index first.',
    );
    exit(1);
  }

  final payload =
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
  final rawPackages = payload['packages'];
  if (rawPackages is! List) {
    stderr.writeln('release-manifest.json has no "packages" list.');
    exit(1);
  }

  final entries = <String>[];
  for (final entry in rawPackages) {
    if (entry is! Map<String, Object?>) continue;
    final name = entry['name'];
    final version = entry['version'];
    if (name is String && version is String) {
      entries.add('$name $version');
    }
  }
  entries.sort();

  if (entries.isEmpty) {
    stdout.writeln('Would publish: (no packages in manifest)');
    return;
  }
  stdout.writeln('Would publish: ${entries.join(', ')}');
}

class _PreviewOptions {
  const _PreviewOptions({required this.outputDirectory});

  final String outputDirectory;

  static _PreviewOptions parse(final List<String> args) {
    var outputDirectory = '${Directory.current.path}/build/registry';
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--output-dir' && i + 1 < args.length) {
        outputDirectory = args[++i];
        break;
      }
    }
    return _PreviewOptions(outputDirectory: outputDirectory);
  }
}
