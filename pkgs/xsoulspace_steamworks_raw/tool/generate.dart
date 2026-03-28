import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final class UpstreamLock {
  const UpstreamLock({
    required this.sdkVersion,
    required this.flatHeaderRelativePath,
    required this.headerSha256,
  });

  final String sdkVersion;
  final String flatHeaderRelativePath;
  final String headerSha256;

  UpstreamLock copyWith({
    final String? sdkVersion,
    final String? flatHeaderRelativePath,
    final String? headerSha256,
  }) => UpstreamLock(
      sdkVersion: sdkVersion ?? this.sdkVersion,
      flatHeaderRelativePath:
          flatHeaderRelativePath ?? this.flatHeaderRelativePath,
      headerSha256: headerSha256 ?? this.headerSha256,
    );

  Map<String, Object?> toJson() => <String, Object?>{
    'sdkVersion': sdkVersion,
    'flatHeaderRelativePath': flatHeaderRelativePath,
    'headerSha256': headerSha256,
  };

  static UpstreamLock fromJson(final Map<String, Object?> json) => UpstreamLock(
      sdkVersion: json['sdkVersion']! as String,
      flatHeaderRelativePath: json['flatHeaderRelativePath']! as String,
      headerSha256: json['headerSha256']! as String,
    );
}

final class GenerateOptions {
  const GenerateOptions({
    required this.checkOnly,
    required this.bumpLock,
    required this.packageRoot,
    required this.sdkPath,
    required this.sdkVersion,
    required this.mockFfigenOutput,
    required this.ffigenExec,
  });

  final bool checkOnly;
  final bool bumpLock;
  final String? packageRoot;
  final String? sdkPath;
  final String? sdkVersion;
  final String? mockFfigenOutput;
  final String? ffigenExec;
}

Future<void> main(final List<String> args) async {
  final options = _parseOptions(args);
  if (options == null) {
    exitCode = 2;
    return;
  }

  if (options.checkOnly && options.bumpLock) {
    stderr.writeln('--check and --bump-lock cannot be used together.');
    exitCode = 2;
    return;
  }

  final cwd = Directory.current.path;
  final packageRoot = p.normalize(
    options.packageRoot == null ? cwd : _resolvePath(cwd, options.packageRoot!),
  );

  final lockPath = p.join(packageRoot, 'tool', 'upstream_lock.json');
  final lockFile = File(lockPath);
  if (!lockFile.existsSync()) {
    stderr.writeln('Missing lock file: $lockPath');
    exitCode = 2;
    return;
  }

  var lock = UpstreamLock.fromJson(
    jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>,
  );

  final sdkPath =
      options.sdkPath ?? Platform.environment['STEAMWORKS_SDK_PATH']?.trim();
  if (sdkPath == null || sdkPath.isEmpty) {
    stderr.writeln(
      'Missing Steamworks SDK path. Provide --sdk-path or STEAMWORKS_SDK_PATH.',
    );
    exitCode = 2;
    return;
  }

  final resolvedSdkPath = p.normalize(_resolvePath(packageRoot, sdkPath));
  final sdkVersion =
      options.sdkVersion ??
      Platform.environment['STEAMWORKS_SDK_VERSION']?.trim() ??
      _readVersionFile(resolvedSdkPath);

  if (sdkVersion.isEmpty) {
    stderr.writeln(
      'Unable to determine SDK version. Set STEAMWORKS_SDK_VERSION '
      'or create <sdk>/steamworks_sdk_version.txt.',
    );
    exitCode = 2;
    return;
  }

  final headerPath = p.join(resolvedSdkPath, lock.flatHeaderRelativePath);
  final headerFile = File(headerPath);
  if (!headerFile.existsSync()) {
    stderr.writeln('Steam flat header not found: $headerPath');
    exitCode = 2;
    return;
  }

  final headerBytes = headerFile.readAsBytesSync();
  final headerSha256 = sha256.convert(headerBytes).toString();

  if (options.bumpLock) {
    lock = lock.copyWith(sdkVersion: sdkVersion, headerSha256: headerSha256);
    lockFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n',
    );
  }

  if (lock.sdkVersion != sdkVersion || lock.headerSha256 != headerSha256) {
    stderr.writeln('Steam SDK lock mismatch:');
    if (lock.sdkVersion != sdkVersion) {
      stderr.writeln(
        ' - sdkVersion lock=${lock.sdkVersion} actual=$sdkVersion',
      );
    }
    if (lock.headerSha256 != headerSha256) {
      stderr.writeln(
        ' - headerSha256 lock=${lock.headerSha256} actual=$headerSha256',
      );
    }
    stderr.writeln(
      'If intentional, run: dart run tool/generate.dart --bump-lock',
    );
    exitCode = 1;
    return;
  }

  final rawOutputPath = p.join(
    packageRoot,
    'lib',
    'src',
    'generated',
    'steam_api_flat_bindings.g.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');
  final shimPath = p.join(packageRoot, 'tool', 'steam_api_flat_shim.h');
  final ffigenTemplatePath = p.join(packageRoot, 'tool', 'ffigen.yaml');

  final touchedFiles = <String>[];
  final mismatches = <String>[];

  final shimContent = _buildShimHeader();
  _checkOrWrite(
    path: shimPath,
    content: shimContent,
    checkOnly: options.checkOnly,
    touchedFiles: touchedFiles,
    mismatches: mismatches,
  );

  final tempDir = await Directory.systemTemp.createTemp(
    'steamworks_raw_codegen_',
  );
  try {
    final tempShimPath = p.join(tempDir.path, 'steam_api_flat_shim.h');
    final tempConfigPath = p.join(tempDir.path, 'ffigen.generated.yaml');
    final tempOutputPath = p.join(
      tempDir.path,
      'steam_api_flat_bindings.g.dart',
    );

    File(tempShimPath).writeAsStringSync(shimContent);

    final ffigenTemplate = File(ffigenTemplatePath).readAsStringSync();
    final tempConfig = _buildFfigenConfig(
      template: ffigenTemplate,
      outputPath: tempOutputPath,
      shimPath: tempShimPath,
      sdkPublicPath: p.join(resolvedSdkPath, 'public'),
    );
    File(tempConfigPath).writeAsStringSync(tempConfig);

    await _runFfigen(
      packageRoot: packageRoot,
      ffigenConfigPath: tempConfigPath,
      outputPath: tempOutputPath,
      mockOutputPath: options.mockFfigenOutput == null
          ? Platform.environment['STEAMWORKS_MOCK_FFIGEN_OUTPUT']
          : _resolvePath(packageRoot, options.mockFfigenOutput!),
      ffigenExec:
          options.ffigenExec ?? Platform.environment['STEAMWORKS_FFIGEN_EXEC'],
    );

    final generatedOutput = File(tempOutputPath).readAsStringSync();
    final processedOutput = _postProcessGeneratedOutput(
      generatedOutput,
      sdkPath: resolvedSdkPath,
    );

    _checkOrWrite(
      path: rawOutputPath,
      content: processedOutput,
      checkOnly: options.checkOnly,
      touchedFiles: touchedFiles,
      mismatches: mismatches,
    );

    final oldSnapshotFile = File(snapshotPath);
    final oldSnapshot = oldSnapshotFile.existsSync()
        ? jsonDecode(oldSnapshotFile.readAsStringSync()) as Map<String, Object?>
        : <String, Object?>{'symbols': <Object?>[]};

    final symbols = _extractSymbols(utf8.decode(headerBytes));
    final newSnapshot = <String, Object?>{
      'sdkVersion': sdkVersion,
      'headerSha256': headerSha256,
      'symbols': symbols,
    };

    final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
        .cast<String>()
        .toSet();
    final newSymbols = symbols.toSet();

    final diff = <String, Object?>{
      'fromSdkVersion': oldSnapshot['sdkVersion'],
      'toSdkVersion': sdkVersion,
      'addedSymbols': (newSymbols.difference(oldSymbols).toList()..sort()),
      'removedSymbols': (oldSymbols.difference(newSymbols).toList()..sort()),
    };

    _checkOrWrite(
      path: snapshotPath,
      content: '${const JsonEncoder.withIndent('  ').convert(newSnapshot)}\n',
      checkOnly: options.checkOnly,
      touchedFiles: touchedFiles,
      mismatches: mismatches,
    );

    _checkOrWrite(
      path: diffPath,
      content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
      checkOnly: options.checkOnly,
      touchedFiles: touchedFiles,
      mismatches: mismatches,
    );

    if (mismatches.isNotEmpty) {
      stderr.writeln('Generated files are out of date:');
      for (final mismatch in mismatches) {
        stderr.writeln(' - ${p.relative(mismatch, from: packageRoot)}');
      }
      stderr.writeln('Run: dart run tool/generate.dart');
      exitCode = 1;
      return;
    }

    if (!options.checkOnly) {
      stdout.writeln('Generated files:');
      for (final file in touchedFiles) {
        stdout.writeln(' - ${p.relative(file, from: packageRoot)}');
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

GenerateOptions? _parseOptions(final List<String> args) {
  var checkOnly = false;
  var bumpLock = false;
  String? packageRoot;
  String? sdkPath;
  String? sdkVersion;
  String? mockFfigenOutput;
  String? ffigenExec;

  String? readValue(final int index, final String flag) {
    if (index + 1 >= args.length) {
      stderr.writeln('Missing value after $flag');
      return null;
    }
    return args[index + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--check':
        checkOnly = true;
      case '--bump-lock':
        bumpLock = true;
      case '--package-root':
        final value = readValue(i, arg);
        if (value == null) {
          return null;
        }
        packageRoot = value;
        i++;
      case '--sdk-path':
        final value = readValue(i, arg);
        if (value == null) {
          return null;
        }
        sdkPath = value;
        i++;
      case '--sdk-version':
        final value = readValue(i, arg);
        if (value == null) {
          return null;
        }
        sdkVersion = value;
        i++;
      case '--mock-ffigen-output':
        final value = readValue(i, arg);
        if (value == null) {
          return null;
        }
        mockFfigenOutput = value;
        i++;
      case '--ffigen-exec':
        final value = readValue(i, arg);
        if (value == null) {
          return null;
        }
        ffigenExec = value;
        i++;
      case '--help':
        stdout.writeln(_usage);
        return null;
      default:
        stderr.writeln('Unknown option: $arg');
        stderr.writeln(_usage);
        return null;
    }
  }

  return GenerateOptions(
    checkOnly: checkOnly,
    bumpLock: bumpLock,
    packageRoot: packageRoot,
    sdkPath: sdkPath,
    sdkVersion: sdkVersion,
    mockFfigenOutput: mockFfigenOutput,
    ffigenExec: ffigenExec,
  );
}

const String _usage = '''
Usage: dart run tool/generate.dart [options]

Options:
  --check                   Verify generated files are up to date.
  --bump-lock               Update upstream_lock.json with current SDK fingerprint.
  --package-root <path>     Override package root (for tests).
  --sdk-path <path>         Override STEAMWORKS_SDK_PATH.
  --sdk-version <version>   Override STEAMWORKS_SDK_VERSION.
  --mock-ffigen-output <p>  Copy this file instead of running ffigen (tests).
  --ffigen-exec <exe>       Custom ffigen executable (advanced).
  --help                    Print usage.
''';

String _readVersionFile(final String sdkRoot) {
  final versionFile = File(p.join(sdkRoot, 'steamworks_sdk_version.txt'));
  if (!versionFile.existsSync()) {
    return '';
  }
  return versionFile.readAsStringSync().trim();
}

String _resolvePath(final String base, final String value) {
  if (p.isAbsolute(value)) {
    return value;
  }
  return p.join(base, value);
}

String _buildShimHeader() => '''
// GENERATED FILE - DO NOT EDIT.
// Shim header used as ffigen entry-point.

#ifndef XSOULSPACE_STEAM_API_FLAT_SHIM_H
#define XSOULSPACE_STEAM_API_FLAT_SHIM_H

#include "steam/steam_api_flat.h"

#endif // XSOULSPACE_STEAM_API_FLAT_SHIM_H
''';

String _buildFfigenConfig({
  required final String template,
  required final String outputPath,
  required final String shimPath,
  required final String sdkPublicPath,
}) => template
      .replaceAll('__OUTPUT_PATH__', _yamlPath(outputPath))
      .replaceAll('__SHIM_HEADER_PATH__', _yamlPath(shimPath))
      .replaceAll('__SDK_PUBLIC_PATH__', _yamlPath(sdkPublicPath));

String _yamlPath(final String value) => value.replaceAll(r'\', '/');

Future<void> _runFfigen({
  required final String packageRoot,
  required final String ffigenConfigPath,
  required final String outputPath,
  required final String? mockOutputPath,
  required final String? ffigenExec,
}) async {
  if (mockOutputPath != null) {
    final mock = File(mockOutputPath);
    if (!mock.existsSync()) {
      throw StateError('Mock ffigen output does not exist: $mockOutputPath');
    }
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(mock.readAsStringSync());
    return;
  }

  ProcessResult result;
  if (ffigenExec != null && ffigenExec.isNotEmpty) {
    result = await Process.run(ffigenExec, <String>[
      '--config',
      ffigenConfigPath,
    ], workingDirectory: packageRoot);
  } else {
    result = await Process.run('dart', <String>[
      'run',
      'ffigen',
      '--config',
      ffigenConfigPath,
    ], workingDirectory: packageRoot);
  }

  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    throw StateError('ffigen failed with exit code ${result.exitCode}');
  }

  final outputFile = File(outputPath);
  if (!outputFile.existsSync()) {
    throw StateError('ffigen did not produce output file: $outputPath');
  }
}

String _postProcessGeneratedOutput(
  final String source, {
  required final String sdkPath,
}) {
  var content = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  content = content.replaceAll(
    sdkPath.replaceAll(r'\', '/'),
    r'$STEAMWORKS_SDK_PATH',
  );
  content = content
      .split('\n')
      .map((final line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
      .join('\n')
      .trimRight();
  return '$content\n';
}

List<String> _extractSymbols(final String headerSource) {
  final symbols = <String>{};
  final lines = const LineSplitter().convert(headerSource);

  final functionPattern = RegExp(r'\b(SteamAPI_[A-Za-z0-9_]+)\s*\(');
  final typedefPattern = RegExp(
    r'^\s*typedef\s+.+?\b([A-Za-z_][A-Za-z0-9_]*)\s*;',
  );
  final enumPattern = RegExp(r'^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)\b');
  final structPattern = RegExp(r'^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)\b');

  for (final line in lines) {
    if (line.contains('S_API')) {
      final function = functionPattern.firstMatch(line);
      if (function != null) {
        symbols.add(function.group(1)!);
      }
    }

    final typedefMatch = typedefPattern.firstMatch(line);
    if (typedefMatch != null) {
      symbols.add(typedefMatch.group(1)!);
    }

    final enumMatch = enumPattern.firstMatch(line);
    if (enumMatch != null) {
      symbols.add(enumMatch.group(1)!);
    }

    final structMatch = structPattern.firstMatch(line);
    if (structMatch != null) {
      symbols.add(structMatch.group(1)!);
    }
  }

  final sorted = symbols.toList()..sort();
  return sorted;
}

void _checkOrWrite({
  required final String path,
  required final String content,
  required final bool checkOnly,
  required final List<String> touchedFiles,
  required final List<String> mismatches,
}) {
  final file = File(path);
  if (checkOnly) {
    if (!file.existsSync() || file.readAsStringSync() != content) {
      mismatches.add(path);
    }
    return;
  }

  if (!file.existsSync() || file.readAsStringSync() != content) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    touchedFiles.add(path);
  }
}
