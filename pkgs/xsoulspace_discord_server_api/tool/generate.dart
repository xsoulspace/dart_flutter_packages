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
    required this.routesHash,
    required this.typesHash,
  });

  final String packageName;
  final String version;
  final String integrity;
  final String tarballSha512;
  final String routesHash;
  final String typesHash;

  UpstreamLock copyWith({
    final String? packageName,
    final String? version,
    final String? integrity,
    final String? tarballSha512,
    final String? routesHash,
    final String? typesHash,
  }) {
    return UpstreamLock(
      packageName: packageName ?? this.packageName,
      version: version ?? this.version,
      integrity: integrity ?? this.integrity,
      tarballSha512: tarballSha512 ?? this.tarballSha512,
      routesHash: routesHash ?? this.routesHash,
      typesHash: typesHash ?? this.typesHash,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'package': packageName,
    'version': version,
    'integrity': integrity,
    'tarballSha512': tarballSha512,
    'routesHash': routesHash,
    'typesHash': typesHash,
  };

  static UpstreamLock fromJson(final Map<String, Object?> json) {
    return UpstreamLock(
      packageName: json['package']! as String,
      version: json['version']! as String,
      integrity: json['integrity']! as String,
      tarballSha512: json['tarballSha512']! as String,
      routesHash: json['routesHash']! as String,
      typesHash: json['typesHash']! as String,
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
  final routeIndexPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'rest_v10_route_index.json',
  );
  final typeIndexPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'rest_v10_type_index.json',
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

  final tempDir = await Directory.systemTemp.createTemp(
    'discord_types_codegen_',
  );

  try {
    final extractedRoot = await _extractTarball(
      tempDir: tempDir,
      bytes: tarballBytes,
    );

    final routeIndex = _buildRouteIndex(extractedRoot, lock);
    final typeIndex = _buildTypeIndex(extractedRoot, lock);

    final routeIndexContent =
        '${const JsonEncoder.withIndent('  ').convert(routeIndex)}\n';
    final typeIndexContent =
        '${const JsonEncoder.withIndent('  ').convert(typeIndex)}\n';

    final expectedLock = lock.copyWith(
      version: registryInfo.version,
      integrity: registryInfo.integrity,
      tarballSha512: sha512Hex(tarballBytes),
      routesHash: sha256Hex(utf8.encode(routeIndexContent)),
      typesHash: sha256Hex(utf8.encode(typeIndexContent)),
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

    final routeSymbols = (routeIndex['routes']! as List<dynamic>)
        .cast<String>()
        .map((final value) => 'route:$value');
    final typeSymbols = (typeIndex['exportedSymbols']! as List<dynamic>)
        .cast<String>()
        .map((final value) => 'type:$value');

    final symbols = <String>{...routeSymbols, ...typeSymbols}.toList()..sort();

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

    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: routeIndexPath,
      content: routeIndexContent,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: typeIndexPath,
      content: typeIndexContent,
      checkOnly: options.checkOnly,
      edits: edits,
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

Future<String> _extractTarball({
  required final Directory tempDir,
  required final List<int> bytes,
}) async {
  final tarballPath = p.join(tempDir.path, 'discord_api_types.tgz');
  File(tarballPath).writeAsBytesSync(bytes, flush: true);

  final extractResult = await Process.run('tar', <String>[
    '-xzf',
    tarballPath,
    '-C',
    tempDir.path,
  ]);

  if (extractResult.exitCode != 0) {
    stderr.writeln(extractResult.stdout);
    stderr.writeln(extractResult.stderr);
    throw StateError('Failed to extract discord-api-types tarball.');
  }

  final packageRoot = p.join(tempDir.path, 'package');
  if (!Directory(packageRoot).existsSync()) {
    throw StateError('discord-api-types tarball did not extract package root.');
  }

  return packageRoot;
}

Map<String, Object?> _buildRouteIndex(
  final String extractedRoot,
  final UpstreamLock lock,
) {
  final interfacesPath = p.join(
    extractedRoot,
    '_generated_',
    'rest',
    'v10',
    'interfaces.d.ts',
  );

  final file = File(interfacesPath);
  if (!file.existsSync()) {
    throw StateError('Missing route declarations file: $interfacesPath');
  }

  final content = file.readAsStringSync();

  final routesBody = _extractInterfaceBody(content, 'RoutesDeclarations');
  final cdnRoutesBody = _extractInterfaceBody(content, 'CDNRoutesDeclarations');

  final routes = _extractRouteMethodNames(routesBody);
  final cdnRoutes = _extractRouteMethodNames(cdnRoutesBody);

  return <String, Object?>{
    'sourcePackage': lock.packageName,
    'version': lock.version,
    'routesSource': '_generated_/rest/v10/interfaces.d.ts',
    'routes': routes,
    'cdnRoutes': cdnRoutes,
    'routesCount': routes.length,
    'cdnRoutesCount': cdnRoutes.length,
  };
}

Map<String, Object?> _buildTypeIndex(
  final String extractedRoot,
  final UpstreamLock lock,
) {
  final restDir = Directory(p.join(extractedRoot, 'rest', 'v10'));
  final payloadDir = Directory(p.join(extractedRoot, 'payloads', 'v10'));

  if (!restDir.existsSync() || !payloadDir.existsSync()) {
    throw StateError('Missing rest/v10 or payloads/v10 declarations.');
  }

  final restFiles = _collectDtsFiles(restDir);
  final payloadFiles = _collectDtsFiles(payloadDir);

  final exportedSymbols = <String>{};

  for (final file in <File>[...restFiles, ...payloadFiles]) {
    final content = file.readAsStringSync();
    final matches = RegExp(
      r'^\s*export\s+(?:declare\s+)?(?:interface|type|enum|class|const|function)\s+([A-Za-z_][A-Za-z0-9_]*)',
      multiLine: true,
    ).allMatches(content);
    for (final match in matches) {
      final symbol = match.group(1);
      if (symbol != null && symbol.isNotEmpty) {
        exportedSymbols.add(symbol);
      }
    }
  }

  final restRelative =
      restFiles
          .map((final file) => p.relative(file.path, from: extractedRoot))
          .toList()
        ..sort();
  final payloadRelative =
      payloadFiles
          .map((final file) => p.relative(file.path, from: extractedRoot))
          .toList()
        ..sort();

  final sortedSymbols = exportedSymbols.toList()..sort();

  return <String, Object?>{
    'sourcePackage': lock.packageName,
    'version': lock.version,
    'restV10Files': restRelative,
    'payloadV10Files': payloadRelative,
    'restFileCount': restRelative.length,
    'payloadFileCount': payloadRelative.length,
    'exportedSymbols': sortedSymbols,
    'exportedSymbolCount': sortedSymbols.length,
  };
}

List<File> _collectDtsFiles(final Directory root) {
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((final file) => file.path.endsWith('.d.ts'))
      .toList(growable: false)
    ..sort((final a, final b) => a.path.compareTo(b.path));
}

String _extractInterfaceBody(final String content, final String interfaceName) {
  final marker = 'export interface $interfaceName';
  final start = content.indexOf(marker);
  if (start < 0) {
    throw StateError('Interface `$interfaceName` was not found.');
  }

  final openBrace = content.indexOf('{', start);
  if (openBrace < 0) {
    throw StateError('Interface `$interfaceName` has no opening brace.');
  }

  var depth = 0;
  for (var i = openBrace; i < content.length; i += 1) {
    final char = content[i];
    if (char == '{') {
      depth += 1;
    } else if (char == '}') {
      depth -= 1;
      if (depth == 0) {
        return content.substring(openBrace + 1, i);
      }
    }
  }

  throw StateError('Interface `$interfaceName` has no closing brace.');
}

List<String> _extractRouteMethodNames(final String interfaceBody) {
  final methods = RegExp(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    multiLine: true,
  ).allMatches(interfaceBody);

  return methods
      .map((final match) => match.group(1))
      .whereType<String>()
      .toList(growable: false)
    ..sort();
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
  if (lock.routesHash != expected.routesHash) {
    mismatches.add(
      'routesHash lock=${lock.routesHash} actual=${expected.routesHash}',
    );
  }
  if (lock.typesHash != expected.typesHash) {
    mismatches.add(
      'typesHash lock=${lock.typesHash} actual=${expected.typesHash}',
    );
  }

  return mismatches;
}
