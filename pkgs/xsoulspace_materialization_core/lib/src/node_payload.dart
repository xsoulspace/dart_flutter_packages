import 'dart:convert';
import 'package:yaml/yaml.dart' show YamlList, YamlMap, loadYaml;

/// The create-file action name served through the ONE edit verb when the
/// binding declares the [FileCreation] capability. One name for every
/// creation-capable class (the semantics are class-agnostic: whole-file
/// meaning creation); the class teaches its anchor currency through the
/// capability's declared fields, never through a per-format verb.
const fileCreationAction = 'create_document';

/// A value admitted for a node edit. Transport keeps the legacy `body`
/// string, but the materializer boundary distinguishes declared prose from a
/// scalar configuration value before any bytes are planned.
sealed class NodeEditPayload {
  const NodeEditPayload();
}

class ProseNodeEditPayload extends NodeEditPayload {
  const ProseNodeEditPayload(this.text);
  final String text;
}

class ScalarNodeEditPayload extends NodeEditPayload {
  const ScalarNodeEditPayload(this.source, this.value);

  /// The exact legal source fragment to splice.
  final String source;

  /// The parsed scalar type: String, num, bool, or null.
  final Object? value;
}

class NodeEditPayloadError implements Exception {
  const NodeEditPayloadError(this.reason, this.hint);
  final String reason;
  final String hint;
}

NodeEditPayload _legacyPayload(String fileClass, String? body) {
  if (body == null || body.isEmpty) {
    throw const NodeEditPayloadError(
      'missing required edit payload',
      "supply the action's declared prose body or typed scalar value",
    );
  }
  if (fileClass == 'md') return ProseNodeEditPayload(body);
  return _parseScalarPayload(body, fileClass: fileClass);
}

ScalarNodeEditPayload _parseScalarPayload(
  String source, {
  required String fileClass,
}) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    throw const NodeEditPayloadError(
      'empty scalar payload',
      'supply a declared scalar value',
    );
  }
  return ScalarNodeEditPayload(
    source,
    _decodeScalar(source, fileClass: fileClass),
  );
}

Object? _decodeScalar(String source, {required String fileClass}) {
  final Object? value;
  try {
    value = fileClass == 'json' ? jsonDecode(source) : loadYaml(source);
  } on Object {
    throw NodeEditPayloadError(
      '$fileClass scalar is not parseable',
      'supply a valid $fileClass string, number, boolean, or null value',
    );
  }
  if (value is YamlMap || value is YamlList || value is Map || value is List) {
    throw NodeEditPayloadError(
      '$fileClass payload must be a scalar',
      'objects, maps, and lists require a declared structured-value schema',
    );
  }
  if (value is double && !value.isFinite) {
    throw NodeEditPayloadError(
      '$fileClass scalar must be finite',
      'supply a finite number, string, boolean, or null value',
    );
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw NodeEditPayloadError(
    '$fileClass payload type is unsupported',
    'supply a string, finite number, boolean, or null value',
  );
}

bool _sameScalarValue(Object? parsed, Object? declared) =>
    parsed == declared && parsed.runtimeType == declared.runtimeType;

bool _targetsExecutableConfigSlot(String anchor) => RegExp(
  r'(^|[.\[])\s*(?:command|commands|script|scripts|shell|exec|run)'
  r'(?:\s*\]|\s*\.|\s*$)',
  caseSensitive: false,
).hasMatch(anchor);

/// Validates the typed payload at the binding boundary and returns the legacy
/// body fragment expected by existing materializers. This keeps transport
/// compatibility without allowing an undifferentiated body to cross admission.
String admitNodeEditPayload({
  required String fileClass,
  required String action,
  NodeEditPayload? payload,
  String? legacyBody,
  String anchor = '',
}) {
  if (fileClass != 'md' && fileClass != 'yaml' && fileClass != 'json') {
    return legacyBody ?? '';
  }
  final allowedActions = switch (fileClass) {
    'md' => const {
      'replace_section',
      'insert_section',
      'append_to_section',
      fileCreationAction,
    },
    _ => const {
      'set_key',
      'replace_value',
      'append_list_item',
      'delete_key',
      fileCreationAction,
    },
  };
  if (!allowedActions.contains(action)) {
    throw NodeEditPayloadError(
      'unsupported $fileClass payload action "$action"',
      'use an action declared by this binding; unsupported schemas have no payload admission',
    );
  }
  if (action == 'delete_key') return legacyBody ?? '';
  if ((fileClass == 'yaml' || fileClass == 'json') &&
      action == fileCreationAction &&
      anchor.isEmpty) {
    if (legacyBody == null || legacyBody.isEmpty) return '';
    throw const NodeEditPayloadError(
      'whole configuration documents have no generated payload slot',
      'create an empty document, then edit a declared non-executable keypath with a typed scalar value',
    );
  }
  if ((fileClass == 'yaml' || fileClass == 'json') &&
      _targetsExecutableConfigSlot(anchor)) {
    throw const NodeEditPayloadError(
      'executable configuration slots do not admit generated values',
      'edit a declared non-executable scalar slot or use a reviewed executable configuration workflow',
    );
  }
  final admitted = payload ?? _legacyPayload(fileClass, legacyBody);
  if (fileClass == 'md') {
    if (admitted is! ProseNodeEditPayload) {
      throw const NodeEditPayloadError(
        'Markdown action requires a prose payload',
        'supply ProseNodeEditPayload; scalar configuration values cannot become prose',
      );
    }
    if (RegExp(
      r'^\s*(?:```|~~~)|^(?: {4}|\t)|<\/?script\b',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(admitted.text)) {
      throw const NodeEditPayloadError(
        'embedded code is not valid Markdown prose payload',
        'route code through a declared code materializer or an explicit review proposal',
      );
    }
    return admitted.text;
  }
  if (fileClass == 'yaml' || fileClass == 'json') {
    if (admitted is! ScalarNodeEditPayload) {
      throw const NodeEditPayloadError(
        'keypath action requires a typed scalar payload',
        'supply ScalarNodeEditPayload; prose cannot be inferred as configuration data',
      );
    }
    final parsed = _decodeScalar(admitted.source, fileClass: fileClass);
    if (!_sameScalarValue(parsed, admitted.value)) {
      throw const NodeEditPayloadError(
        'typed scalar source does not match its declared value',
        'supply a payload whose source parses to exactly its typed scalar value',
      );
    }
    return admitted.source;
  }
  return legacyBody ?? '';
}

/// The FILE-CREATION capability, declared as binding data (build order
/// item 7): the binding declares WHETHER the class supports creation and
/// in which anchor currency — not a per-format verb, not a raw write.
///
/// The router addresses creation at a DIR node (the parent in the
/// map-graph); the anchor names the new file (workspace-relative), so
/// the path PROJECTS from meaning and the jail never sees a model-named
/// absolute path. The class's initial-content semantics (heading-bearing
/// body for heading classes; empty map document + first key at the
/// anchor keypath for keypath classes) live in the class's materializer
/// — the capability declares the CONTRACT (action + currency), the
/// materializer realizes it, and the registry linter keeps them honest.
class FileCreation {
  const FileCreation({required this.action, required this.anchorCurrency});

  /// The create-file action name (one of the ONE verb's servable
  /// actions for this class). Use [fileCreationAction].
  final String action;

  /// The creation anchor's declared currency:
  /// - `new_file_path` — the anchor is the new file's workspace-relative
  ///   path; the initial content rides the body whole (heading classes:
  ///   the body must carry the initial heading structure);
  /// - `new_file_path#keypath` — the anchor is the path plus an optional
  ///   `#keypath` suffix; the suffix sets the FIRST key into the created
  ///   empty map document (keypath classes), the body being its value.
  final String anchorCurrency;
}
