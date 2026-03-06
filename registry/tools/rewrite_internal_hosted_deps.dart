import 'dart:io';

import '_pubspec_rewriter.dart';
import '_registry_workspace.dart';

Future<void> main(final List<String> args) async {
  final options = _RewriteOptions.parse(args);
  final packages = await discoverPackages(
    repoRoot: options.repoRoot,
    includePrivate: false,
  );
  final packageMap = mapPackagesByName(packages);
  final internalNames = packageMap.keys.toSet();
  final internalVersions = {
    for (final package in packages) package.name: package.version,
  };

  final selectedPackages = options.packageFilter == null
      ? packages
      : packages
            .where(
              (final package) => options.packageFilter!.contains(package.name),
            )
            .toList(growable: false);

  var filesChanged = 0;
  var rewrites = 0;

  for (final package in selectedPackages) {
    final result = rewriteHostedDependencies(
      content: package.pubspecContent,
      internalPackageNames: internalNames,
      internalPackageVersions: internalVersions,
      hostedUrl: options.hostedUrl,
    );

    if (!result.changed) {
      continue;
    }

    filesChanged += 1;
    rewrites += result.rewrites;
    stdout.writeln('Updated ${package.relativePubspecPath}');
    for (final detail in result.details) {
      stdout.writeln('  - $detail');
    }

    if (!options.dryRun) {
      await File(package.pubspecPath).writeAsString(result.content);
    }
  }

  if (filesChanged == 0) {
    stdout.writeln('No internal dependency rewrites were required.');
    return;
  }

  stdout.writeln(
    options.dryRun
        ? 'Dry run complete: $filesChanged pubspec(s), $rewrites dependency rewrite(s).'
        : 'Rewrote $filesChanged pubspec(s), $rewrites dependency rewrite(s).',
  );
}

class _RewriteOptions {
  const _RewriteOptions({
    required this.repoRoot,
    required this.hostedUrl,
    required this.dryRun,
    required this.packageFilter,
  });

  final String repoRoot;
  final String hostedUrl;
  final bool dryRun;
  final Set<String>? packageFilter;

  static _RewriteOptions parse(final List<String> args) {
    var repoRoot = Directory.current.path;
    var hostedUrl = 'https://pub.xsoulspace.dev';
    var dryRun = false;
    Set<String>? packageFilter;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--repo-root':
          repoRoot = args[++index];
        case '--hosted-url':
          hostedUrl = normalizeUrl(args[++index]);
        case '--dry-run':
          dryRun = true;
        case '--packages':
          packageFilter = args[++index]
              .split(',')
              .map((final name) => name.trim())
              .where((final name) => name.isNotEmpty)
              .toSet();
        default:
          stderr.writeln('Unknown argument: $arg');
          _printUsageAndExit();
      }
    }

    return _RewriteOptions(
      repoRoot: repoRoot,
      hostedUrl: hostedUrl,
      dryRun: dryRun,
      packageFilter: packageFilter,
    );
  }
}

Never _printUsageAndExit() {
  stderr.writeln(
    'Usage: dart registry/tools/rewrite_internal_hosted_deps.dart '
    '[--repo-root <path>] [--hosted-url <url>] [--packages a,b] [--dry-run]',
  );
  exit(64);
}
