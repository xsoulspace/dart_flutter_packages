import 'dart:convert';

/// Portable immutable source/candidate data. No authority, IO or journal.
///
/// The native host resolves [workspaceIdentity] before constructing this value.
/// A stored observation or check receipt is never a fresh promotion grant.
final class TextChangeCandidate {
  factory TextChangeCandidate({
    required String workspaceIdentity,
    required String originTaskId,
    String? originActorRef,
    required Map<String, String?> observedSource,
    required Map<String, String?> intendedChanges,
    required String verificationDescription,
    Map<String, Object?> checkEvidence = const {},
    required int maxDecodedBytes,
  }) {
    final budget = _JsonBudget(maxDecodedBytes);
    final json =
        budget.copy({
              'version': 1,
              'workspaceIdentity': workspaceIdentity,
              'originTaskId': originTaskId,
              'originActorRef': ?originActorRef,
              'observedSource': observedSource,
              'intendedChanges': intendedChanges,
              'verificationDescription': verificationDescription,
              'checkEvidence': checkEvidence,
            })
            as Map<String, Object?>;
    return TextChangeCandidate._validated(json);
  }

  TextChangeCandidate._(
    this._canonicalJson, {
    required this.workspaceIdentity,
    required this.originTaskId,
    required this.originActorRef,
    required this.observedSource,
    required this.intendedChanges,
    required this.verificationDescription,
    required this.checkEvidence,
  });

  factory TextChangeCandidate.fromJson(
    Map<String, Object?> json, {
    required int maxDecodedBytes,
  }) {
    final copied =
        _JsonBudget(maxDecodedBytes).copy(json) as Map<String, Object?>;
    return TextChangeCandidate._validated(copied);
  }

  /// Reads the canonical representation produced by [canonicalJson]. Requiring
  /// canonical input also rejects duplicate keys and ambiguous JSON encodings.
  factory TextChangeCandidate.decode(
    String json, {
    required int maxDecodedBytes,
  }) {
    final budget = _JsonBudget(maxDecodedBytes);
    budget.checkRaw(json);
    final value = jsonDecode(json);
    if (value is! Map<String, Object?>) {
      throw const FormatException('text_candidate: expected JSON object');
    }
    final candidate = TextChangeCandidate.fromJson(
      value,
      maxDecodedBytes: maxDecodedBytes,
    );
    if (candidate.canonicalJson != json) {
      throw const FormatException('text_candidate: noncanonical JSON');
    }
    return candidate;
  }

  static TextChangeCandidate _validated(Map<String, Object?> json) {
    const requiredKeys = {
      'version',
      'workspaceIdentity',
      'originTaskId',
      'observedSource',
      'intendedChanges',
      'verificationDescription',
      'checkEvidence',
    };
    const allowedKeys = {...requiredKeys, 'originActorRef'};
    if (!json.keys.toSet().containsAll(requiredKeys) ||
        json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('text_candidate: invalid fields');
    }
    if (json['version'] is! int || json['version'] != 1) {
      throw const FormatException('text_candidate: unsupported version');
    }
    final workspace = _nonempty(json['workspaceIdentity'], 'workspaceIdentity');
    // This is lexical validation only. Filesystem canonicalization, identity
    // comparison, symlink policy and promotion stay with the native owner.
    if (!_absoluteWorkspace(workspace)) {
      throw const FormatException('text_candidate: invalid workspace identity');
    }
    final task = _nonempty(json['originTaskId'], 'originTaskId');
    final actor = json['originActorRef'];
    if (actor != null) _nonempty(actor, 'originActorRef');
    final description = _nonempty(
      json['verificationDescription'],
      'verificationDescription',
    );
    final observed = _textMap(json['observedSource'], 'observedSource');
    final changes = _textMap(json['intendedChanges'], 'intendedChanges');
    if (changes.isEmpty) {
      throw const FormatException('text_candidate: empty changes');
    }
    for (final entry in changes.entries) {
      if (!observed.containsKey(entry.key)) {
        throw const FormatException('text_candidate: unobserved change');
      }
      if (observed[entry.key] == entry.value) {
        throw const FormatException('text_candidate: no-op change');
      }
    }
    final evidence = json['checkEvidence'];
    if (evidence is! Map<String, Object?>) {
      throw const FormatException('text_candidate: invalid check evidence');
    }
    // Omit a null optional origin exactly as the constructor does.
    final canonical = <String, Object?>{...json}
      ..removeWhere((key, value) => key == 'originActorRef' && value == null);
    return TextChangeCandidate._(
      jsonEncode(_sorted(canonical)),
      workspaceIdentity: workspace,
      originTaskId: task,
      originActorRef: actor as String?,
      observedSource: observed,
      intendedChanges: changes,
      verificationDescription: description,
      checkEvidence: evidence,
    );
  }

  final String workspaceIdentity;
  final String originTaskId;
  final String? originActorRef;
  final Map<String, String?> observedSource;
  final Map<String, String?> intendedChanges;
  final String verificationDescription;
  final Map<String, Object?> checkEvidence;
  final String _canonicalJson;

  /// Sorted keys at every object level; exact strings and nulls are preserved.
  /// Native consumers may hash these UTF-8 bytes for content addressing.
  String get canonicalJson => _canonicalJson;

  /// Fresh, mutable JSON data; mutating it cannot change this snapshot.
  Map<String, Object?> toJson() =>
      jsonDecode(_canonicalJson) as Map<String, Object?>;
}

String _nonempty(Object? value, String field) {
  if (value is! String || value.trim().isEmpty || value.contains('\u0000')) {
    throw FormatException('text_candidate: invalid $field');
  }
  return value;
}

bool _absoluteWorkspace(String value) {
  if (value.trim() != value ||
      value.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    return false;
  }
  String remainder;
  if (value.startsWith('/')) {
    if (value.contains('\\')) return false;
    if (value == '/') return true;
    remainder = value.substring(1);
  } else if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
    remainder = value.substring(3).replaceAll('\\', '/');
    if (remainder.isEmpty) return true;
  } else if (value.startsWith(r'\\')) {
    remainder = value.substring(2).replaceAll('\\', '/');
    if (remainder.split('/').length < 2) return false;
  } else {
    return false;
  }
  return !remainder
      .split('/')
      .any((part) => part.isEmpty || part == '.' || part == '..');
}

Map<String, String?> _textMap(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw FormatException('text_candidate: invalid $field');
  }
  final out = <String, String?>{};
  for (final entry in value.entries) {
    _relativePath(entry.key);
    if (entry.value != null && entry.value is! String) {
      throw FormatException('text_candidate: unsupported $field value');
    }
    out[entry.key] = entry.value as String?;
  }
  return Map.unmodifiable(out);
}

void _relativePath(String path) {
  if (path.isEmpty ||
      path.trim() != path ||
      path.startsWith('/') ||
      path.contains('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path) ||
      path.codeUnits.any((unit) => unit < 32 || unit == 127) ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('text_candidate: invalid relative path');
  }
}

Object? _sorted(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List<Object?>) return value.map(_sorted).toList();
  return value;
}

final class _JsonBudget {
  _JsonBudget(this.maximum) {
    if (maximum <= 0) {
      throw const FormatException('text_candidate: invalid byte budget');
    }
  }
  final int maximum;
  int used = 0;
  final Set<Object> _active = Set.identity();

  void _charge(int bytes) {
    used += bytes;
    if (used > maximum) {
      throw const FormatException(
        'text_candidate: decoded byte budget exceeded',
      );
    }
  }

  void checkRaw(String value) {
    if (value.length > maximum || utf8.encode(value).length > maximum) {
      throw const FormatException(
        'text_candidate: decoded byte budget exceeded',
      );
    }
  }

  Object? copy(Object? value, [int depth = 0]) {
    if (depth > 64) {
      throw const FormatException('text_candidate: JSON nesting exceeded');
    }
    switch (value) {
      case null:
        _charge(4);
        return null;
      case bool():
        _charge(value ? 4 : 5);
        return value;
      case String():
        if (value.length > maximum - used) {
          throw const FormatException(
            'text_candidate: decoded byte budget exceeded',
          );
        }
        _wellFormed(value);
        _charge(utf8.encode(jsonEncode(value)).length);
        return value;
      case int():
        _charge(value.toString().length);
        return value;
      case double():
        if (!value.isFinite) {
          throw const FormatException('text_candidate: nonfinite JSON number');
        }
        _charge(jsonEncode(value).length);
        return value;
      case Map():
        if (!_active.add(value)) {
          throw const FormatException('text_candidate: cyclic JSON');
        }
        try {
          _charge(2);
          final out = <String, Object?>{};
          for (final entry in value.entries) {
            if (entry.key is! String) {
              throw const FormatException('text_candidate: nonstring JSON key');
            }
            if (out.isNotEmpty) _charge(1);
            final key = copy(entry.key, depth + 1) as String;
            _charge(1);
            out[key] = copy(entry.value, depth + 1);
          }
          return Map<String, Object?>.unmodifiable(out);
        } finally {
          _active.remove(value);
        }
      case List():
        if (!_active.add(value)) {
          throw const FormatException('text_candidate: cyclic JSON');
        }
        try {
          _charge(2);
          final out = <Object?>[];
          for (final item in value) {
            if (out.isNotEmpty) _charge(1);
            out.add(copy(item, depth + 1));
          }
          return List<Object?>.unmodifiable(out);
        } finally {
          _active.remove(value);
        }
      default:
        throw const FormatException('text_candidate: unsupported JSON value');
    }
  }
}

void _wellFormed(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (++i == units.length || units[i] < 0xDC00 || units[i] > 0xDFFF) {
        throw const FormatException('text_candidate: malformed Unicode');
      }
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const FormatException('text_candidate: malformed Unicode');
    }
  }
}
