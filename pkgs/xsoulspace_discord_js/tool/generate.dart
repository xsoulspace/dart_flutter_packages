import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

final class UpstreamLock {
  const UpstreamLock({
    required this.packageName,
    required this.version,
    required this.integrity,
    required this.tarballSha512,
    required this.declarationHash,
  });

  final String packageName;
  final String version;
  final String integrity;
  final String tarballSha512;
  final String declarationHash;

  UpstreamLock copyWith({
    final String? packageName,
    final String? version,
    final String? integrity,
    final String? tarballSha512,
    final String? declarationHash,
  }) {
    return UpstreamLock(
      packageName: packageName ?? this.packageName,
      version: version ?? this.version,
      integrity: integrity ?? this.integrity,
      tarballSha512: tarballSha512 ?? this.tarballSha512,
      declarationHash: declarationHash ?? this.declarationHash,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'package': packageName,
    'version': version,
    'integrity': integrity,
    'tarballSha512': tarballSha512,
    'declarationHash': declarationHash,
  };

  static UpstreamLock fromJson(final Map<String, Object?> json) {
    return UpstreamLock(
      packageName: json['package']! as String,
      version: json['version']! as String,
      integrity: json['integrity']! as String,
      tarballSha512: json['tarballSha512']! as String,
      declarationHash: json['declarationHash']! as String,
    );
  }
}

final class GenerateOptions {
  const GenerateOptions({required this.checkOnly, required this.bump});

  final bool checkOnly;
  final bool bump;
}

Future<void> main(final List<String> args) async {
  final options = _parseOptions(args);
  if (options == null) {
    exitCode = 2;
    return;
  }

  if (options.checkOnly && options.bump) {
    stderr.writeln('--check and --bump cannot be used together.');
    exitCode = 2;
    return;
  }

  final packageRoot = Directory.current.path;
  final lockPath = p.join(packageRoot, 'tool', 'upstream_lock.json');
  final dtsOutputPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'discord_embedded_sdk.generated.d.ts',
  );
  final rawOutputPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'discord_raw.g.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');

  final lockFile = File(lockPath);
  if (!lockFile.existsSync()) {
    stderr.writeln('Missing lock file: $lockPath');
    exitCode = 2;
    return;
  }

  var lock = UpstreamLock.fromJson(
    jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>,
  );

  final registryInfo = await fetchRegistryVersionInfo(
    Uri.encodeComponent(lock.packageName),
    lock.version,
  );

  final tarballBytes = await downloadTarball(registryInfo.tarball);
  verifyIntegrity(lock.integrity, tarballBytes);

  final tempDir = await Directory.systemTemp.createTemp('discord_codegen_');

  try {
    final flattenedDts = await _flattenDiscordDeclarations(
      packageRoot: packageRoot,
      tempDir: tempDir,
      tarballBytes: tarballBytes,
      version: lock.version,
    );

    final expectedLock = lock.copyWith(
      version: registryInfo.version,
      integrity: registryInfo.integrity,
      tarballSha512: sha512Hex(tarballBytes),
      declarationHash: sha256Hex(utf8.encode(flattenedDts)),
    );

    final lockMismatches = _lockMismatches(lock, expectedLock);
    if (lockMismatches.isNotEmpty && !options.bump) {
      stderr.writeln('Upstream lock mismatch:');
      for (final line in lockMismatches) {
        stderr.writeln(' - $line');
      }
      stderr.writeln('Run: dart run tool/generate.dart --bump');
      exitCode = 1;
      return;
    }

    if (options.bump) {
      lock = expectedLock;
      lockFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n',
      );
    }

    final parser = TypeScriptIrParser.fromSharedCore(
      currentPackageRoot: packageRoot,
    );
    await parser.ensureDependencies();

    final tempDtsPath = p.join(tempDir.path, 'discord_sdk_flattened.d.ts');
    File(tempDtsPath).writeAsStringSync(flattenedDts);

    final ir = await parser.parseFileToIr(tempDtsPath);

    final rawCode = _emitRawCode(lock.version);

    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: dtsOutputPath,
      content: flattenedDts,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: rawOutputPath,
      content: rawCode,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    final parserSymbols = (ir['symbols']! as List<dynamic>).cast<String>();
    final symbols = _extractSymbols(
      dtsContent: flattenedDts,
      parserSymbols: parserSymbols,
    );
    final newSnapshot = <String, Object?>{
      'sdkVersion': lock.version,
      'symbols': symbols,
    };

    final snapshotFile = File(snapshotPath);
    final oldSnapshot = snapshotFile.existsSync()
        ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>
        : <String, Object?>{'symbols': <Object?>[]};

    final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
        .cast<String>()
        .toSet();
    final newSymbols = symbols.toSet();

    final diff = buildApiDiff(
      fromVersion: oldSnapshot['sdkVersion'],
      toVersion: lock.version,
      oldSymbols: oldSymbols,
      newSymbols: newSymbols,
      fromVersionField: 'fromVersion',
      toVersionField: 'toVersion',
    );

    checkOrWriteGeneratedFile(
      path: snapshotPath,
      content: '${const JsonEncoder.withIndent('  ').convert(newSnapshot)}\n',
      checkOnly: options.checkOnly,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: diffPath,
      content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
      checkOnly: options.checkOnly,
      edits: edits,
    );

    if (edits.hasMismatches) {
      stderr.writeln('Generated files are out of date:');
      for (final mismatch in edits.mismatches) {
        stderr.writeln(' - ${p.relative(mismatch, from: packageRoot)}');
      }
      stderr.writeln('Run: dart run tool/generate.dart');
      exitCode = 1;
      return;
    }

    if (!options.checkOnly) {
      stdout.writeln('Generated files:');
      for (final file in edits.touchedFiles) {
        stdout.writeln(' - ${p.relative(file, from: packageRoot)}');
      }
      if (lockMismatches.isNotEmpty && options.bump) {
        stdout.writeln(
          'Updated lock file: ${p.relative(lockPath, from: packageRoot)}',
        );
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<String> _flattenDiscordDeclarations({
  required final String packageRoot,
  required final Directory tempDir,
  required final List<int> tarballBytes,
  required final String version,
}) async {
  final tarballPath = p.join(tempDir.path, 'discord_sdk.tgz');
  File(tarballPath).writeAsBytesSync(tarballBytes, flush: true);

  final extractResult = await Process.run('tar', <String>[
    '-xzf',
    tarballPath,
    '-C',
    tempDir.path,
  ]);

  if (extractResult.exitCode != 0) {
    stderr.writeln(extractResult.stdout);
    stderr.writeln(extractResult.stderr);
    throw StateError('Failed to extract npm tarball for Discord SDK.');
  }

  final packageDir = p.join(tempDir.path, 'package');
  final outputDir = Directory(p.join(packageDir, 'output'));
  if (!outputDir.existsSync()) {
    throw StateError('Discord SDK tarball does not contain package/output.');
  }

  final files =
      outputDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((final file) => file.path.endsWith('.d.ts'))
          .toList(growable: false)
        ..sort((final a, final b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    throw StateError('No TypeScript declaration files found in Discord SDK.');
  }

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT.')
    ..writeln('// Source: @discord/embedded-app-sdk@$version')
    ..writeln('// Flattened declarations for parser/emitter compatibility.')
    ..writeln();

  for (final file in files) {
    final rel = p.relative(file.path, from: packageDir);
    final normalized = _normalizeDts(file.readAsStringSync());
    if (normalized.trim().isEmpty) {
      continue;
    }

    buffer.writeln('// ===== $rel =====');
    buffer.writeln(normalized.trimRight());
    buffer.writeln();
  }

  buffer.writeln('export interface DiscordEmbeddedSdkGlobalEntry {');
  buffer.writeln(
    '  new (clientId: string, configuration?: SdkConfiguration): IDiscordSDK;',
  );
  buffer.writeln('}');
  buffer.writeln(
    'export declare const DiscordSDK: DiscordEmbeddedSdkGlobalEntry;',
  );

  return '${buffer.toString().trimRight()}\n';
}

String _normalizeDts(final String content) {
  final lines = content.split('\n');
  final normalized = <String>[];

  for (var line in lines) {
    final trimmed = line.trimLeft();

    if (trimmed.startsWith('import ')) {
      continue;
    }
    if (trimmed.startsWith('export {')) {
      continue;
    }
    if (trimmed == 'export {};') {
      continue;
    }
    if (trimmed.startsWith('/// <reference')) {
      continue;
    }

    if (trimmed.startsWith('export default ')) {
      line = line.replaceFirst('export default ', 'export ');
    }

    if (trimmed.startsWith('declare ') &&
        !trimmed.startsWith('declare global')) {
      line = line.replaceFirst(
        RegExp(r'^(\s*)declare\s+'),
        r'$1export declare ',
      );
    }

    normalized.add(line);
  }

  return normalized.join('\n');
}

GenerateOptions? _parseOptions(final List<String> args) {
  var checkOnly = false;
  var bump = false;

  for (final arg in args) {
    switch (arg) {
      case '--check':
        checkOnly = true;
      case '--bump':
        bump = true;
      case '--help':
        stdout.writeln('Usage: dart run tool/generate.dart [--check] [--bump]');
        return null;
      default:
        stderr.writeln('Unknown option: $arg');
        return null;
    }
  }

  return GenerateOptions(checkOnly: checkOnly, bump: bump);
}

List<String> _lockMismatches(
  final UpstreamLock lock,
  final UpstreamLock expected,
) {
  final mismatches = <String>[];

  if (lock.version != expected.version) {
    mismatches.add('version lock=${lock.version} actual=${expected.version}');
  }
  if (lock.integrity != expected.integrity) {
    mismatches.add(
      'integrity lock=${lock.integrity} actual=${expected.integrity}',
    );
  }
  if (lock.tarballSha512 != expected.tarballSha512) {
    mismatches.add(
      'tarballSha512 lock=${lock.tarballSha512} actual=${expected.tarballSha512}',
    );
  }
  if (lock.declarationHash != expected.declarationHash) {
    mismatches.add(
      'declarationHash lock=${lock.declarationHash} actual=${expected.declarationHash}',
    );
  }

  return mismatches;
}

String _emitRawCode(final String sdkVersion) {
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: @discord/embedded-app-sdk@$sdkVersion
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('DiscordSDK')
external JSAny? get DiscordSDK;

extension type DiscordSdkRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> ready();

  external JSAny? get commands;

  external JSPromise<JSAny?> subscribe(
    JSString event,
    JSFunction listener, [
    JSAny? subscribeArgs,
  ]);

  external JSPromise<JSAny?> unsubscribe(
    JSString event,
    JSFunction listener, [
    JSAny? unsubscribeArgs,
  ]);
}
''';
}

List<String> _extractSymbols({
  required final String dtsContent,
  required final List<String> parserSymbols,
}) {
  final symbols = <String>{...parserSymbols};
  final regex = RegExp(
    r'^(?:export\s+)?(?:declare\s+)?(?:interface|type|enum|class|const|function)\s+([A-Za-z_][A-Za-z0-9_]*)',
    multiLine: true,
  );
  for (final match in regex.allMatches(dtsContent)) {
    final symbol = match.group(1);
    if (symbol != null && symbol.isNotEmpty) {
      symbols.add(symbol);
    }
  }

  final sorted = symbols.toList()..sort();
  return sorted;
}
