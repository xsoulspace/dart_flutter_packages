import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _excludedPackages = <String>{
  'xsoulspace_steamworks',
  'xsoulspace_steamworks_raw',
  'xsoulspace_platform_steam',
};

final _wipReadmePatterns = <RegExp>[
  RegExp(r'\bwork\s+in\s+progress\b', caseSensitive: false),
  RegExp(r'\bwip\b', caseSensitive: false),
  RegExp(r'not\s+ready\s+for\s+production', caseSensitive: false),
  RegExp(r'not\s+production\s+ready', caseSensitive: false),
  RegExp(r'placeholder\s+implementation', caseSensitive: false),
];

Future<void> main(final List<String> args) async {
  final options = _Options.parse(args);
  final repoRoot = Directory.current.path;
  final pkgsDir = Directory('$repoRoot/pkgs');

  if (!pkgsDir.existsSync()) {
    stderr.writeln('pkgs directory not found. Run from monorepo root.');
    exit(2);
  }

  final packageDirs =
      pkgsDir
          .listSync()
          .whereType<Directory>()
          .where(
            (final dir) =>
                basename(dir.path).startsWith('xsoulspace_') &&
                !_excludedPackages.contains(basename(dir.path)) &&
                File('${dir.path}/pubspec.yaml').existsSync(),
          )
          .toList(growable: false)
        ..sort((final a, final b) => a.path.compareTo(b.path));

  final reports = <Map<String, Object?>>[];

  for (final dir in packageDirs) {
    final packageName = basename(dir.path);
    final pubspecFile = File('${dir.path}/pubspec.yaml');
    final pubspec = await pubspecFile.readAsString();
    final isInternal = RegExp(
      r'^publish_to:\s*none\s*$',
      multiLine: true,
    ).hasMatch(pubspec);

    if (options.scope == _Scope.publicOnly && isInternal) {
      continue;
    }
    if (options.scope == _Scope.internalOnly && !isInternal) {
      continue;
    }

    final isFlutterPackage = RegExp(r'sdk:\s*flutter').hasMatch(pubspec);

    stdout.writeln('=== $packageName ===');

    final checks = <_CheckResult>[];
    final requiredChecks = <String>{};

    void registerRequired(final String name) {
      requiredChecks.add(name);
    }

    registerRequired('docs_files');
    registerRequired('readme_status');
    registerRequired('pub_get');
    registerRequired('analyze');
    registerRequired('test');
    if (!isInternal) {
      registerRequired('no_local_path_overrides');
      registerRequired('publish_dry_run');
    }

    final docs = _checkDocs(dir.path);
    checks.add(docs.filesCheck);
    checks.add(docs.readmeCheck);

    if (!isInternal) {
      checks.add(_checkNoLocalPath(pubspec));
    }

    final pubGetCommand = isFlutterPackage
        ? <String>['flutter', 'pub', 'get']
        : <String>['dart', 'pub', 'get'];

    final pubGet = await _runCommand(
      name: 'pub_get',
      command: pubGetCommand,
      workingDirectory: dir.path,
    );
    checks.add(pubGet);

    final canRunPostResolutionChecks = pubGet.passed;

    if (canRunPostResolutionChecks) {
      final analyzeCommand = isFlutterPackage
          ? <String>[
              'flutter',
              'analyze',
              '--no-fatal-infos',
              '--no-fatal-warnings',
            ]
          : <String>['dart', 'analyze'];
      checks.add(
        await _runCommand(
          name: 'analyze',
          command: analyzeCommand,
          workingDirectory: dir.path,
        ),
      );

      final testCommand = isFlutterPackage
          ? <String>['flutter', 'test']
          : <String>['dart', 'test'];
      checks.add(
        await _runCommand(
          name: 'test',
          command: testCommand,
          workingDirectory: dir.path,
        ),
      );

      if (!isInternal) {
        final publishCommand = isFlutterPackage
            ? <String>['flutter', 'pub', 'publish', '--dry-run']
            : <String>['dart', 'pub', 'publish', '--dry-run'];
        checks.add(
          await _runCommand(
            name: 'publish_dry_run',
            command: publishCommand,
            workingDirectory: dir.path,
          ),
        );
      }
    } else {
      checks.add(
        const _CheckResult.skipped(
          name: 'analyze',
          reason: 'Skipped because pub_get failed.',
        ),
      );
      checks.add(
        const _CheckResult.skipped(
          name: 'test',
          reason: 'Skipped because pub_get failed.',
        ),
      );
      if (!isInternal) {
        checks.add(
          const _CheckResult.skipped(
            name: 'publish_dry_run',
            reason: 'Skipped because pub_get failed.',
          ),
        );
      }
    }

    final failingChecks = checks
        .where((final check) => requiredChecks.contains(check.name))
        .where((final check) => !check.passed)
        .map((final check) => check.name)
        .toList(growable: false);

    final status = failingChecks.isEmpty
        ? (isInternal ? 'ready_internal' : 'ready_public')
        : 'blocked';

    reports.add({
      'package': packageName,
      'status': status,
      'is_internal': isInternal,
      'checks': checks.map((final check) => check.toJson()).toList(),
      'failing_checks': failingChecks,
    });
  }

  final readyPublic = reports.where((final report) {
    return report['status'] == 'ready_public';
  }).length;
  final readyInternal = reports.where((final report) {
    return report['status'] == 'ready_internal';
  }).length;
  final blocked = reports.where((final report) {
    return report['status'] == 'blocked';
  }).length;

  final artifact = <String, Object?>{
    'evaluated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'scope': options.scope.name,
    'excluded_packages': _excludedPackages.toList(growable: false),
    'summary': {
      'ready_public': readyPublic,
      'ready_internal': readyInternal,
      'blocked': blocked,
      'total': reports.length,
    },
    'packages': reports,
  };

  final outputFile = File(
    options.outputPath.startsWith('/')
        ? options.outputPath
        : '$repoRoot/${options.outputPath}',
  );

  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
  );

  stdout.writeln('Artifact written: ${outputFile.path}');
  stdout.writeln(
    'Summary: ready_public=$readyPublic, '
    'ready_internal=$readyInternal, blocked=$blocked',
  );

  if (options.failOnBlocked && blocked > 0) {
    exit(1);
  }
}

_CheckResult _checkNoLocalPath(final String pubspecContent) {
  final hasLocalPath = RegExp(
    r'^\s*path:\s*(\.{1,2}/|/)',
    multiLine: true,
  ).hasMatch(pubspecContent);

  if (hasLocalPath) {
    return const _CheckResult.failure(
      name: 'no_local_path_overrides',
      reason: 'Public package contains local path dependency/override.',
    );
  }

  return const _CheckResult.success(name: 'no_local_path_overrides');
}

_RequiredDocsChecks _checkDocs(final String packageDir) {
  const requiredFiles = <String>['README.md', 'CHANGELOG.md', 'LICENSE'];
  final missing = requiredFiles
      .where((final file) => !File('$packageDir/$file').existsSync())
      .toList(growable: false);

  final filesCheck = missing.isEmpty
      ? const _CheckResult.success(name: 'docs_files')
      : _CheckResult.failure(
          name: 'docs_files',
          reason: 'Missing required docs files: ${missing.join(', ')}',
        );

  final readmeFile = File('$packageDir/README.md');
  if (!readmeFile.existsSync()) {
    return _RequiredDocsChecks(
      filesCheck: filesCheck,
      readmeCheck: const _CheckResult.failure(
        name: 'readme_status',
        reason: 'README.md is missing.',
      ),
    );
  }

  final readmeContent = readmeFile.readAsStringSync();
  final hasWipText = _wipReadmePatterns.any(
    (final pattern) => pattern.hasMatch(readmeContent),
  );

  return _RequiredDocsChecks(
    filesCheck: filesCheck,
    readmeCheck: hasWipText
        ? const _CheckResult.failure(
            name: 'readme_status',
            reason:
                'README contains non-production wording (WIP/not-ready/placeholder).',
          )
        : const _CheckResult.success(name: 'readme_status'),
  );
}

Future<_CheckResult> _runCommand({
  required final String name,
  required final List<String> command,
  required final String workingDirectory,
}) async {
  final process = await Process.start(
    command.first,
    command.sublist(1),
    workingDirectory: workingDirectory,
    runInShell: true,
  );

  final stdoutFuture = _tailProcessOutput(process.stdout);
  final stderrFuture = _tailProcessOutput(process.stderr);
  final exitCode = await process.exitCode;

  final stdoutTail = await stdoutFuture;
  final stderrTail = await stderrFuture;

  if (exitCode == 0) {
    return _CheckResult.success(name: name, command: command.join(' '));
  }

  final combinedTail = [
    if (stdoutTail.isNotEmpty) 'stdout:\n$stdoutTail',
    if (stderrTail.isNotEmpty) 'stderr:\n$stderrTail',
  ].join('\n\n');

  return _CheckResult.failure(
    name: name,
    reason: 'Command failed (exit=$exitCode).',
    command: command.join(' '),
    outputTail: combinedTail,
  );
}

Future<String> _tailProcessOutput(final Stream<List<int>> stream) async {
  const maxLines = 80;
  final lines = <String>[];

  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    lines.add(line);
    if (lines.length > maxLines) {
      lines.removeAt(0);
    }
  }

  return lines.join('\n');
}

final class _RequiredDocsChecks {
  const _RequiredDocsChecks({
    required this.filesCheck,
    required this.readmeCheck,
  });

  final _CheckResult filesCheck;
  final _CheckResult readmeCheck;
}

final class _CheckResult {
  const _CheckResult.success({required this.name, this.command})
    : passed = true,
      skipped = false,
      reason = null,
      outputTail = null;

  const _CheckResult.failure({
    required this.name,
    required this.reason,
    this.command,
    this.outputTail,
  }) : passed = false,
       skipped = false;

  const _CheckResult.skipped({required this.name, required this.reason})
    : passed = false,
      skipped = true,
      command = null,
      outputTail = null;

  final String name;
  final bool passed;
  final bool skipped;
  final String? reason;
  final String? command;
  final String? outputTail;

  Map<String, Object?> toJson() => {
    'name': name,
    'passed': passed,
    'skipped': skipped,
    if (reason != null) 'reason': reason,
    if (command != null) 'command': command,
    if (outputTail != null && outputTail!.isNotEmpty) 'output_tail': outputTail,
  };
}

enum _Scope { all, publicOnly, internalOnly }

final class _Options {
  const _Options({
    required this.scope,
    required this.outputPath,
    required this.failOnBlocked,
  });

  final _Scope scope;
  final String outputPath;
  final bool failOnBlocked;

  static _Options parse(final List<String> args) {
    var scope = _Scope.all;
    var outputPath = 'tool/artifacts/xsoulspace_production_readiness.json';
    var failOnBlocked = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--scope':
          i++;
          if (i >= args.length) {
            _usageAndExit('Missing value for --scope');
          }
          scope = switch (args[i]) {
            'all' => _Scope.all,
            'public' => _Scope.publicOnly,
            'internal' => _Scope.internalOnly,
            _ => _usageAndExit('Invalid scope: ${args[i]}'),
          };
        case '--output':
          i++;
          if (i >= args.length) {
            _usageAndExit('Missing value for --output');
          }
          outputPath = args[i];
        case '--fail-on-blocked':
          failOnBlocked = true;
        case '--help':
          _usageAndExit(null, exitCode: 0);
        default:
          _usageAndExit('Unknown argument: ${args[i]}');
      }
    }

    return _Options(
      scope: scope,
      outputPath: outputPath,
      failOnBlocked: failOnBlocked,
    );
  }

  static Never _usageAndExit(final String? message, {int exitCode = 2}) {
    if (message != null) {
      stderr.writeln(message);
    }
    stderr.writeln(
      'Usage: dart tool/xsoulspace_production_readiness.dart '
      '[--scope all|public|internal] '
      '[--output path] [--fail-on-blocked]',
    );
    exit(exitCode);
  }
}

String basename(final String path) {
  final separator = Platform.pathSeparator;
  final normalized = path.endsWith(separator)
      ? path.substring(0, path.length - 1)
      : path;
  final index = normalized.lastIndexOf(separator);
  return index == -1 ? normalized : normalized.substring(index + 1);
}
