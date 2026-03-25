import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_paths.dart';

final class TypeScriptIrParser {
  const TypeScriptIrParser({
    required this.parserDir,
    required this.parserScriptPath,
  });

  factory TypeScriptIrParser.fromSharedCore({
    required final String currentPackageRoot,
  }) {
    final coreRoot = resolvePackageRootFromPackageConfig(
      currentPackageRoot: currentPackageRoot,
      packageName: 'xsoulspace_js_interop_codegen',
    );
    final parserDir = p.join(coreRoot, 'tool', 'ts_parser');
    return TypeScriptIrParser(
      parserDir: parserDir,
      parserScriptPath: p.join(parserDir, 'parse_typescript_ir.mjs'),
    );
  }

  final String parserDir;
  final String parserScriptPath;

  Future<void> ensureDependencies() async {
    final typescriptPackage = File(
      p.join(parserDir, 'node_modules', 'typescript', 'package.json'),
    );
    if (typescriptPackage.existsSync()) {
      return;
    }

    final result = await Process.run('npm', <String>[
      'install',
      '--no-audit',
      '--no-fund',
    ], workingDirectory: parserDir);

    if (result.exitCode != 0) {
      stderr.writeln(result.stdout);
      stderr.writeln(result.stderr);
      throw StateError('Failed to install TypeScript parser dependencies');
    }
  }

  Future<Map<String, Object?>> parseFileToIr(final String dtsPath) async {
    final result = await Process.run('node', <String>[
      parserScriptPath,
      dtsPath,
    ], workingDirectory: parserDir);

    if (result.exitCode != 0) {
      stderr.writeln(result.stdout);
      stderr.writeln(result.stderr);
      throw StateError('TypeScript parser failed');
    }

    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }
}
