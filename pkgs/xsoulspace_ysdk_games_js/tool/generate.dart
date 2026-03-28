import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

Future<void> main(final List<String> args) async {
  final packageRoot = Directory.current.path;
  final lockPath = p.join(packageRoot, 'tool', 'upstream_lock.json');
  final rawOutputPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'ysdk_raw.g.dart',
  );
  final wrapperEnumsPath = p.join(
    packageRoot,
    'lib',
    'src',
    'wrapper',
    'enums.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');

  final isCheck = args.contains('--check');
  final bumpIndex = args.indexOf('--bump');
  final bumpVersion = bumpIndex >= 0 && bumpIndex + 1 < args.length
      ? args[bumpIndex + 1]
      : null;

  if (bumpIndex >= 0 && bumpVersion == null) {
    stderr.writeln('Missing version after --bump');
    exitCode = 2;
    return;
  }

  final lockFile = File(lockPath);
  if (!lockFile.existsSync()) {
    stderr.writeln('Missing lock file: $lockPath');
    exitCode = 2;
    return;
  }

  var lockConfig = NpmLockConfig.fromJson(
    jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>,
  );

  final packageEncoded = Uri.encodeComponent(lockConfig.packageName);
  if (bumpVersion != null) {
    final info = await fetchRegistryVersionInfo(packageEncoded, bumpVersion);
    lockConfig = NpmLockConfig(
      packageName: lockConfig.packageName,
      version: info.version,
      integrity: info.integrity,
    );
    if (!isCheck) {
      lockFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(lockConfig.toJson())}\n',
      );
    }
  }

  final versionInfo = await fetchRegistryVersionInfo(
    packageEncoded,
    lockConfig.version,
  );
  if (versionInfo.integrity != lockConfig.integrity) {
    stderr.writeln(
      'Integrity mismatch in lock file for ${lockConfig.packageName}@${lockConfig.version}.\n'
      'Lock: ${lockConfig.integrity}\nRegistry: ${versionInfo.integrity}',
    );
    exitCode = 1;
    return;
  }

  final tarballBytes = await downloadTarball(versionInfo.tarball);
  verifyIntegrity(versionInfo.integrity, tarballBytes);

  final parser = TypeScriptIrParser.fromSharedCore(
    currentPackageRoot: packageRoot,
  );

  final tempDir = await Directory.systemTemp.createTemp('ysdk_codegen_');
  try {
    final dtsPath = await extractTarGzFile(
      tempDir: tempDir.path,
      tarballBytes: tarballBytes,
      selector: (final path) => path.endsWith('/index.d.ts'),
      outputName: 'index.d.ts',
      missingError: 'index.d.ts not found inside npm tarball',
    );
    await parser.ensureDependencies();
    final ir = await parser.parseFileToIr(dtsPath);

    final rawCode = emitRawCode(ir, lockConfig);
    final enumsCode = emitWrapperEnums(ir, lockConfig);

    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: rawOutputPath,
      content: rawCode,
      checkOnly: isCheck,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: wrapperEnumsPath,
      content: enumsCode,
      checkOnly: isCheck,
      edits: edits,
    );

    final newSnapshot = <String, Object?>{
      'package': lockConfig.packageName,
      'version': lockConfig.version,
      'symbols': ((ir['symbols']! as List<dynamic>).cast<String>()..sort()),
    };

    final snapshotFile = File(snapshotPath);
    final oldSnapshot = snapshotFile.existsSync()
        ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>
        : <String, Object?>{'symbols': <Object?>[]};

    final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
        .cast<String>()
        .toSet();
    final newSymbols = (newSnapshot['symbols']! as List<dynamic>)
        .cast<String>()
        .toSet();

    final diff = <String, Object?>{
      'package': lockConfig.packageName,
      ...buildApiDiff(
        fromVersion: oldSnapshot['version'],
        toVersion: lockConfig.version,
        oldSymbols: oldSymbols,
        newSymbols: newSymbols,
      ),
    };

    checkOrWriteGeneratedFile(
      path: snapshotPath,
      content: '${const JsonEncoder.withIndent('  ').convert(newSnapshot)}\n',
      checkOnly: isCheck,
      edits: edits,
    );

    if (!isCheck || bumpVersion != null) {
      checkOrWriteGeneratedFile(
        path: diffPath,
        content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
        checkOnly: false,
        edits: edits,
      );
    }

    if (edits.hasMismatches) {
      stderr.writeln('Generated files are out of date:');
      for (final mismatch in edits.mismatches) {
        stderr.writeln(' - $mismatch');
      }
      stderr.writeln('Run: dart run tool/generate.dart');
      exitCode = 1;
      return;
    }

    if (!isCheck) {
      stdout.writeln('Generated files:');
      for (final path in edits.touchedFiles) {
        stdout.writeln(' - ${p.relative(path, from: packageRoot)}');
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

String emitRawCode(final Map<String, Object?> ir, final NpmLockConfig lock) {
  final declarations = (ir['declarations']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final globalDeclarations = (ir['globalDeclarations']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final knownTypes = declarations
      .map((final d) => d['name']! as String)
      .toSet();

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Source: ${lock.packageName}@${lock.version}')
    ..writeln(
      '// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element',
    )
    ..writeln()
    ..writeln('@JS()')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'dart:js_interop';")
    ..writeln();

  for (final global in globalDeclarations) {
    if (global['kind'] != 'variable') {
      continue;
    }
    final name = global['name'] as String?;
    final typeIr = global['type'] as Map<String, Object?>?;
    if (name == null || typeIr == null || name != 'YaGames') {
      continue;
    }

    final typeLiteralMembers =
        (typeIr['members'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, Object?>>();

    b
      ..writeln("@JS('YaGames')")
      ..writeln('external YaGamesGlobalRaw get yaGames;')
      ..writeln()
      ..writeln(
        'extension type YaGamesGlobalRaw(JSObject _) implements JSObject {',
      );

    emitMembers(
      b,
      knownTypes: knownTypes,
      members: typeLiteralMembers,
      indent: '  ',
      className: 'YaGamesGlobalRaw',
    );

    b
      ..writeln('}')
      ..writeln();
  }

  for (final declaration in declarations) {
    final kind = declaration['kind']! as String;

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
  final members = (declaration['members']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final rawName = '${name}Raw';

  b.writeln('extension type $rawName(JSObject _) implements JSObject {');

  emitMembers(
    b,
    knownTypes: knownTypes,
    members: members,
    indent: '  ',
    className: rawName,
  );

  b
    ..writeln('}')
    ..writeln();
}

void emitMembers(
  final StringBuffer b, {
  required final Set<String> knownTypes,
  required final List<Map<String, Object?>> members,
  required final String indent,
  required final String className,
}) {
  final signatures = <String>{};

  for (final member in members) {
    final memberKind = member['kind'] as String?;

    switch (memberKind) {
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
        b.writeln('$indent external $returnType $dartName$paramsBuffer;');

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
  if (literalUnion.isNotEmpty) {
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
}

void emitEnum(final StringBuffer b, final Map<String, Object?> declaration) {
  final name = declaration['name']! as String;
  final rawName = '${name}Raw';
  final valuesClass = '${rawName}Values';
  b.writeln('typedef $rawName = JSString;');
  b.writeln('abstract final class $valuesClass {');

  final members = (declaration['members']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  for (final member in members) {
    final memberName = member['name']! as String;
    final value = member['value'];
    final fieldName = safeIdentifier(toLowerCamel(memberName));
    final stringValue = value is String ? value : '$value';
    b.writeln(
      "  static JSString get $fieldName => '${escapeSingleQuotes(stringValue)}'.toJS;",
    );
  }

  b
    ..writeln('}')
    ..writeln();
}

String emitWrapperEnums(
  final Map<String, Object?> ir,
  final NpmLockConfig lock,
) {
  final declarations = (ir['declarations']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final literalUnions = (ir['literalUnions']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final enumDecls = declarations
      .where((final d) => d['kind'] == 'enum')
      .toList();

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Source: ${lock.packageName}@${lock.version}')
    ..writeln()
    ..writeln('library;')
    ..writeln();

  for (final union in literalUnions) {
    final enumName = union['name']! as String;
    final values = (union['values']! as List<dynamic>).cast<String>();
    emitDartEnum(b, enumName, values);
  }

  for (final enumDecl in enumDecls) {
    final enumName = enumDecl['name']! as String;
    final members = (enumDecl['members']! as List<dynamic>)
        .cast<Map<String, Object?>>();
    final values = members
        .map((final m) => m['value'])
        .whereType<String>()
        .toList(growable: false);
    emitDartEnum(b, enumName, values);
  }

  return '$b';
}

void emitDartEnum(
  final StringBuffer b,
  final String name,
  final List<String> values,
) {
  if (values.isEmpty) {
    return;
  }

  final used = <String>{};
  final entries = <MapEntry<String, String>>[];
  for (final value in values) {
    var enumCase = safeEnumCaseName(value);
    if (!used.add(enumCase)) {
      enumCase = '${enumCase}_${used.length}';
      used.add(enumCase);
    }
    entries.add(MapEntry(enumCase, value));
  }

  b.writeln('enum $name {');
  for (final entry in entries) {
    b.writeln("  ${entry.key}('${escapeSingleQuotes(entry.value)}'),");
  }
  var fallbackCase = 'unknownValue';
  if (used.contains(fallbackCase)) {
    fallbackCase = 'unknownValue_${used.length + 1}';
  }

  b
    ..writeln("  $fallbackCase('__unknown__');")
    ..writeln()
    ..writeln('  const $name(this.value);')
    ..writeln('  final String value;')
    ..writeln()
    ..writeln('  static $name fromValue(final String? value) {')
    ..writeln('    if (value == null) return $fallbackCase;')
    ..writeln('    for (final item in $name.values) {')
    ..writeln('      if (item.value == value) return item;')
    ..writeln('    }')
    ..writeln('    return $fallbackCase;')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

String mapTypeToDart(
  final Map<String, Object?>? typeIr, {
  required final Set<String> knownTypes,
  required final bool forReturn,
}) {
  if (typeIr == null) {
    return forReturn ? 'JSAny?' : 'JSAny?';
  }

  final kind = typeIr['kind'] as String?;

  switch (kind) {
    case 'keyword':
      final name = typeIr['name']! as String;
      return switch (name) {
        'string' => 'JSString',
        'number' => 'JSNumber',
        'boolean' => 'JSBoolean',
        'void' => forReturn ? 'void' : 'JSAny?',
        _ => 'JSAny?',
      };

    case 'reference':
      final name = typeIr['name']! as String;
      final typeArgs = (typeIr['typeArgs'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, Object?>>();
      if (name == 'Promise') {
        final argType = typeArgs.isEmpty
            ? 'JSAny?'
            : mapTypeToDart(
                typeArgs.first,
                knownTypes: knownTypes,
                forReturn: false,
              );
        return 'JSPromise<$argType>';
      }
      if (name == 'Array') {
        final argType = typeArgs.isEmpty
            ? 'JSAny?'
            : mapTypeToDart(
                typeArgs.first,
                knownTypes: knownTypes,
                forReturn: false,
              );
        return 'JSArray<$argType>';
      }
      if (name == 'Record') {
        return 'JSObject';
      }
      if (knownTypes.contains(name)) {
        return '${name}Raw';
      }
      return switch (name) {
        'Error' => 'JSObject',
        _ => 'JSAny?',
      };

    case 'array':
      final elementType = mapTypeToDart(
        typeIr['elementType'] as Map<String, Object?>?,
        knownTypes: knownTypes,
        forReturn: false,
      );
      return 'JSArray<$elementType>';

    case 'union':
      final types = (typeIr['types']! as List<dynamic>)
          .cast<Map<String, Object?>>();
      if (types.isEmpty) {
        return 'JSAny?';
      }

      final nonNullable = <Map<String, Object?>>[];
      var hasNullable = false;
      for (final t in types) {
        if (t['kind'] == 'keyword' &&
            ((t['name'] == 'null') || (t['name'] == 'undefined'))) {
          hasNullable = true;
        } else {
          nonNullable.add(t);
        }
      }

      if (nonNullable.length == 1) {
        final base = mapTypeToDart(
          nonNullable.first,
          knownTypes: knownTypes,
          forReturn: forReturn,
        );
        return hasNullable ? makeNullable(base) : base;
      }

      final allStringLiteral =
          nonNullable.isNotEmpty &&
          nonNullable.every(
            (final t) => t['kind'] == 'literal' && t['valueType'] == 'string',
          );
      if (allStringLiteral) {
        return hasNullable ? 'JSString?' : 'JSString';
      }

      return 'JSAny?';

    case 'literal':
      final valueType = typeIr['valueType'] as String?;
      return switch (valueType) {
        'string' => 'JSString',
        'number' => 'JSNumber',
        'boolean' => 'JSBoolean',
        _ => 'JSAny?',
      };

    case 'tuple':
      return 'JSArray<JSAny?>';

    case 'typeQuery':
      return 'JSObject';

    case 'parenthesized':
      return mapTypeToDart(
        typeIr['type'] as Map<String, Object?>?,
        knownTypes: knownTypes,
        forReturn: forReturn,
      );

    default:
      return 'JSAny?';
  }
}

String makeNullable(final String typeName) {
  if (typeName.endsWith('?') || typeName == 'void') {
    return typeName;
  }
  return '$typeName?';
}

String safeIdentifier(final String raw, {final String fallback = 'value'}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  final cleaned = trimmed
      .replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')
      .replaceAll(RegExp('_+'), '_');

  var candidate = cleaned;
  if (candidate.isEmpty) {
    candidate = fallback;
  }
  if (RegExp('^[0-9]').hasMatch(candidate)) {
    candidate = '_$candidate';
  }

  const keywords = <String>{
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  };

  if (keywords.contains(candidate)) {
    candidate = '${candidate}Value';
  }

  return candidate;
}

String safeEnumCaseName(final String rawValue) {
  if (rawValue.isEmpty) {
    return 'empty';
  }
  final lowered = rawValue.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  return safeIdentifier(lowered);
}

String toLowerCamel(final String value) {
  if (value.isEmpty) {
    return value;
  }

  final parts = value
      .split(RegExp('[^a-zA-Z0-9]+'))
      .where((final part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return value;
  }

  final first = parts.first.toLowerCase();
  final rest = parts
      .skip(1)
      .map(
        (final part) => part[0].toUpperCase() + part.substring(1).toLowerCase(),
      )
      .join();
  return '$first$rest';
}

String escapeSingleQuotes(final String value) => value.replaceAll("'", r"\'");
