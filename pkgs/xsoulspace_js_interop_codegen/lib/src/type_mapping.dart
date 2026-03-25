String mapTypeToDart(
  final Map<String, Object?>? typeIr, {
  required final Set<String> knownTypes,
  required final bool forReturn,
}) {
  if (typeIr == null) {
    return 'JSAny?';
  }

  final kind = typeIr['kind'] as String?;

  switch (kind) {
    case 'keyword':
      final name = typeIr['name'] as String;
      return switch (name) {
        'string' => 'JSString',
        'number' => 'JSNumber',
        'boolean' => 'JSBoolean',
        'void' => forReturn ? 'void' : 'JSAny?',
        _ => 'JSAny?',
      };

    case 'reference':
      final name = typeIr['name'] as String;
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
      final types = (typeIr['types'] as List<dynamic>)
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
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  var candidate = cleaned;
  if (candidate.isEmpty) {
    candidate = fallback;
  }
  if (RegExp(r'^[0-9]').hasMatch(candidate)) {
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
  final lowered = rawValue.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return safeIdentifier(lowered, fallback: 'value');
}

String toLowerCamel(final String value) {
  if (value.isEmpty) {
    return value;
  }

  final parts = value
      .split(RegExp(r'[^a-zA-Z0-9]+'))
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
