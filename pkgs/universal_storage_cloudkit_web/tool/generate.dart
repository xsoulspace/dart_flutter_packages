import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

Future<void> main(final List<String> args) async {
  final checkOnly = _parseCheckOnly(args);
  if (checkOnly == null) {
    exitCode = 2;
    return;
  }

  final packageRoot = Directory.current.path;
  final dtsPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'cloudkit.generated.d.ts',
  );
  final rawPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'cloudkit_raw.g.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');

  final dtsFile = File(dtsPath);
  if (!dtsFile.existsSync()) {
    stderr.writeln('Missing CloudKit d.ts snapshot: $dtsPath');
    exitCode = 2;
    return;
  }

  final dtsContent = dtsFile.readAsStringSync();
  final parser = TypeScriptIrParser.fromSharedCore(
    currentPackageRoot: packageRoot,
  );
  await parser.ensureDependencies();

  final ir = await parser.parseFileToIr(dtsPath);
  final rawCode = emitRawCode(ir);

  final symbols =
      ((ir['symbols'] as List<dynamic>? ?? <dynamic>[]).cast<String>()..sort())
          .toList(growable: false);

  final globalSymbols =
      ((ir['globalDeclarations'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, Object?>>()
              .where((final value) => value['kind'] == 'variable')
              .map((final value) => value['name'] as String?)
              .whereType<String>()
              .toList()
            ..sort())
          .toList(growable: false);

  final sourceHash = sha256Hex(utf8.encode(dtsContent));
  final snapshot = <String, Object?>{
    'source': 'tool/generated/cloudkit.generated.d.ts',
    'sourceHash': sourceHash,
    'generated': 'lib/src/raw/cloudkit_raw.g.dart',
    'symbolCount': symbols.length,
    'symbols': symbols,
    'globalSymbols': globalSymbols,
  };

  final snapshotFile = File(snapshotPath);
  final oldSnapshot = snapshotFile.existsSync()
      ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>
      : <String, Object?>{'symbols': <Object?>[]};

  final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
      .cast<String>()
      .toSet();
  final newSymbols = symbols.toSet();

  final diff = <String, Object?>{
    'source': snapshot['source'],
    ...buildApiDiff(
      fromVersion: oldSnapshot['sourceHash'],
      toVersion: sourceHash,
      oldSymbols: oldSymbols,
      newSymbols: newSymbols,
      fromVersionField: 'fromSourceHash',
      toVersionField: 'toSourceHash',
    ),
  };

  final edits = GenerationEdits();
  checkOrWriteGeneratedFile(
    path: rawPath,
    content: rawCode,
    checkOnly: checkOnly,
    edits: edits,
  );
  checkOrWriteGeneratedFile(
    path: snapshotPath,
    content: '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
    checkOnly: checkOnly,
    edits: edits,
  );
  checkOrWriteGeneratedFile(
    path: diffPath,
    content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
    checkOnly: checkOnly,
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

  if (!checkOnly) {
    stdout.writeln('Generated files:');
    for (final path in edits.touchedFiles) {
      stdout.writeln(' - ${p.relative(path, from: packageRoot)}');
    }
  }
}

bool? _parseCheckOnly(final List<String> args) {
  var checkOnly = false;
  for (final arg in args) {
    if (arg == '--check') {
      checkOnly = true;
      continue;
    }
    if (arg == '--help') {
      stdout.writeln('Usage: dart run tool/generate.dart [--check]');
      return null;
    }
    stderr.writeln('Unknown option: $arg');
    return null;
  }
  return checkOnly;
}

String emitRawCode(final Map<String, Object?> ir) {
  final declarations = (ir['declarations'] as List<dynamic>? ?? <dynamic>[])
      .cast<Map<String, Object?>>();
  final globalDeclarations =
      (ir['globalDeclarations'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, Object?>>();

  final knownTypes = declarations
      .map((final declaration) => declaration['name']! as String)
      .toSet();

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Source: CloudKit JS declaration snapshot')
    ..writeln(
      '// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element',
    )
    ..writeln()
    ..writeln('@JS()')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'dart:js_interop';")
    ..writeln();

  final cloudKitGlobal = globalDeclarations.firstWhere(
    (final global) =>
        global['kind'] == 'variable' && global['name'] == 'CloudKit',
    orElse: () => const <String, Object?>{},
  );

  if (cloudKitGlobal.isNotEmpty) {
    final typeIr = cloudKitGlobal['type'] as Map<String, Object?>?;
    final mappedType = mapTypeToDart(
      typeIr,
      knownTypes: knownTypes,
      forReturn: true,
    );

    b
      ..writeln("@JS('CloudKit')")
      ..writeln('external $mappedType get cloudKitGlobal;');
  } else {
    b
      ..writeln("@JS('CloudKit')")
      ..writeln('external JSAny? get cloudKitGlobal;');
  }

  b
    ..writeln('bool get hasCloudKitGlobal => cloudKitGlobal != null;')
    ..writeln();

  for (final declaration in declarations) {
    final kind = declaration['kind'] as String?;
    switch (kind) {
      case 'interface':
        emitInterface(b, declaration, knownTypes);
      case 'typeAlias':
        emitTypeAlias(b, declaration, knownTypes);
      case 'enum':
        emitEnum(b, declaration);
      default:
        break;
    }
  }

  return '$b';
}

void emitInterface(
  final StringBuffer b,
  final Map<String, Object?> declaration,
  final Set<String> knownTypes,
) {
  final name = declaration['name']! as String;
  final members = (declaration['members'] as List<dynamic>? ?? <dynamic>[])
      .cast<Map<String, Object?>>();
  final rawName = '${name}Raw';

  b.writeln('extension type $rawName(JSObject _) implements JSObject {');

  emitMembers(b, knownTypes: knownTypes, members: members, indent: '  ');

  b
    ..writeln('}')
    ..writeln();
}

void emitMembers(
  final StringBuffer b, {
  required final Set<String> knownTypes,
  required final List<Map<String, Object?>> members,
  required final String indent,
}) {
  final signatures = <String>{};

  for (final member in members) {
    final kind = member['kind'] as String?;

    switch (kind) {
      case 'property':
      case 'getter':
        final name = member['name'] as String?;
        if (name == null) {
          continue;
        }

        final dartName = safeIdentifier(name);
        final typeIr = member['type'] as Map<String, Object?>?;
        var typeName = mapTypeToDart(
          typeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );
        if ((member['optional'] as bool?) ?? false) {
          typeName = makeNullable(typeName);
        }

        final signature = 'get:$name:$typeName';
        if (!signatures.add(signature)) {
          continue;
        }

        if (dartName != name) {
          b.writeln("$indent@JS('${escapeSingleQuotes(name)}')");
        }
        b.writeln('$indent external $typeName get $dartName;');

      case 'method':
        final name = member['name'] as String?;
        if (name == null) {
          continue;
        }

        final dartName = safeIdentifier(name);
        final params = (member['params'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, Object?>>();
        final returnTypeIr = member['returnType'] as Map<String, Object?>?;
        final returnType = mapTypeToDart(
          returnTypeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );

        final parameterChunks = <String>[];
        var optionalStart = -1;

        for (var i = 0; i < params.length; i++) {
          final param = params[i];
          final paramName = safeIdentifier(
            param['name'] as String? ?? 'arg$i',
            fallback: 'arg$i',
          );
          final paramTypeIr = param['type'] as Map<String, Object?>?;
          var paramType = mapTypeToDart(
            paramTypeIr,
            knownTypes: knownTypes,
            forReturn: false,
          );

          final isOptional = (param['optional'] as bool?) ?? false;
          final isRest = (param['rest'] as bool?) ?? false;

          if (isRest) {
            paramType = 'JSArray<JSAny?>';
          }
          if (isOptional) {
            paramType = makeNullable(paramType);
            optionalStart = optionalStart == -1 ? i : optionalStart;
          }

          parameterChunks.add('$paramType $paramName');
        }

        final signature =
            'method:$name:$returnType:${parameterChunks.join(',')}';
        if (!signatures.add(signature)) {
          continue;
        }

        final paramsBuffer = StringBuffer();
        if (parameterChunks.isEmpty) {
          paramsBuffer.write('()');
        } else if (optionalStart == -1) {
          paramsBuffer.write('(${parameterChunks.join(', ')})');
        } else {
          final required = parameterChunks.take(optionalStart).toList();
          final optional = parameterChunks.skip(optionalStart).toList();
          paramsBuffer.write('(');
          if (required.isNotEmpty) {
            paramsBuffer.write(required.join(', '));
            if (optional.isNotEmpty) {
              paramsBuffer.write(', ');
            }
          }
          paramsBuffer.write('[');
          paramsBuffer.write(optional.join(', '));
          paramsBuffer.write(']');
          paramsBuffer.write(')');
        }

        if (dartName != name) {
          b.writeln("$indent@JS('${escapeSingleQuotes(name)}')");
        }
        b.writeln(
          '$indent external $returnType $dartName$paramsBuffer;',
        );

      case 'index':
        final returnTypeIr = member['returnType'] as Map<String, Object?>?;
        final returnType = mapTypeToDart(
          returnTypeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );

        final signature = 'index:$returnType';
        if (!signatures.add(signature)) {
          continue;
        }

        b.writeln('$indent external $returnType operator [](JSAny? key);');

      default:
        break;
    }
  }
}

void emitTypeAlias(
  final StringBuffer b,
  final Map<String, Object?> declaration,
  final Set<String> knownTypes,
) {
  final name = declaration['name']! as String;
  final rawName = '${name}Raw';
  final typeParams =
      (declaration['typeParams'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, Object?>>();
  final typeIr = declaration['type'] as Map<String, Object?>?;

  final mappedType = mapTypeToDart(
    typeIr,
    knownTypes: knownTypes,
    forReturn: true,
  );

  if (typeParams.isEmpty) {
    b.writeln('typedef $rawName = $mappedType;');
  } else {
    final genericArgs = <String>[];
    for (var i = 0; i < typeParams.length; i++) {
      genericArgs.add('T$i extends JSAny?');
    }
    b.writeln('typedef $rawName<${genericArgs.join(', ')}> = $mappedType;');
  }

  final literalUnion =
      (declaration['literalUnion'] as List<dynamic>? ?? <dynamic>[])
          .cast<dynamic>();
  if (literalUnion.isEmpty) {
    return;
  }

  final valuesClass = '${rawName}Values';
  b.writeln('abstract final class $valuesClass {');

  final usedNames = <String>{};
  for (final value in literalUnion) {
    final rawValue = value as String;
    var fieldName = safeIdentifier(toLowerCamel(rawValue));
    if (!usedNames.add(fieldName)) {
      fieldName = '${fieldName}_${usedNames.length}';
      usedNames.add(fieldName);
    }

    b.writeln(
      "  static JSString get $fieldName => '${escapeSingleQuotes(rawValue)}'.toJS;",
    );
  }

  b
    ..writeln('}')
    ..writeln();
}

void emitEnum(final StringBuffer b, final Map<String, Object?> declaration) {
  final name = declaration['name']! as String;
  final rawName = '${name}Raw';
  final valuesClass = '${rawName}Values';

  b.writeln('typedef $rawName = JSString;');
  b.writeln('abstract final class $valuesClass {');

  final members = (declaration['members'] as List<dynamic>? ?? <dynamic>[])
      .cast<Map<String, Object?>>();
  for (final member in members) {
    final memberName = member['name']! as String;
    final value = member['value'];
    final fieldName = safeIdentifier(
      toLowerCamel(memberName),
    );
    final stringValue = value is String ? value : '$value';
    b.writeln(
      "  static JSString get $fieldName => '${escapeSingleQuotes(stringValue)}'.toJS;",
    );
  }

  b
    ..writeln('}')
    ..writeln();
}
