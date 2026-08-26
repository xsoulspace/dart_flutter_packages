// ignore_for_file: lines_longer_than_80_chars

/// Deterministic checker evaluation for coding tasks.
///
/// Checkers run against the jail workspace after the agent finishes. They are
/// pure functions of (workspace, spec) → pass/fail so results are comparable
/// across agents and models.
library;

import 'dart:convert';
import 'dart:io';

import 'task_spec.dart';

/// Result of evaluating one checker.
class CheckerResult {
  CheckerResult({required this.passed, required this.detail});
  final bool passed;
  final String detail;
}

/// Evaluate [spec] against the jail rooted at [root].
CheckerResult evaluateChecker(CheckerSpec spec, String root) {
  switch (spec.type) {
    case 'file_exists':
      return _simple(
        spec.path != null && File('$root/${spec.path}').existsSync(),
        'file ${spec.path} exists',
      );
    case 'contains':
      return _onFile(root, spec, (content) {
        final missing = [
          if (spec.value != null && !content.contains(spec.value!)) spec.value!,
          ...spec.values.where((v) => !content.contains(v)),
        ];
        return _simple(
          missing.isEmpty,
          missing.isEmpty
              ? 'all values present in ${spec.path}'
              : 'missing from ${spec.path}: $missing',
        );
      });
    case 'not_contains':
      return _onFile(root, spec, (content) {
        final forbidden = [
          if (spec.value != null && content.contains(spec.value!)) spec.value!,
          ...spec.values.where(content.contains),
        ];
        return _simple(
          forbidden.isEmpty,
          forbidden.isEmpty
              ? 'no forbidden values in ${spec.path}'
              : 'forbidden values present in ${spec.path}: $forbidden',
        );
      });
    case 'equals':
      return _onFile(root, spec, (content) {
        final expected = spec.value ?? '';
        return _simple(
          content.trim() == expected.trim(),
          'content ${content.trim() == expected.trim() ? '==' : '!='} expected '
          '(got ${content.length} chars, want ${expected.length})',
        );
      });
    case 'regex':
      return _onFile(root, spec, (content) {
        final re = RegExp(spec.pattern ?? '', multiLine: true);
        return _simple(
          re.hasMatch(content),
          'pattern ${spec.pattern} ${re.hasMatch(content) ? 'matched' : 'not matched'}'
          ' in ${spec.path}',
        );
      });
    case 'json_valid':
      return _onFile(root, spec, (content) {
        try {
          jsonDecode(content);
          return _simple(true, '${spec.path} is valid JSON');
        } on FormatException catch (e) {
          return _simple(false, '${spec.path} invalid JSON: ${e.message}');
        }
      });
    default:
      throw ArgumentError('unknown checker type: ${spec.type}');
  }
}

CheckerResult _simple(bool ok, String detail) =>
    CheckerResult(passed: ok, detail: detail);

CheckerResult _onFile(
  String root,
  CheckerSpec spec,
  CheckerResult Function(String content) fn,
) {
  final path = spec.path;
  if (path == null) {
    return CheckerResult(passed: false, detail: '${spec.type}: no path given');
  }
  final file = File('$root/$path');
  if (!file.existsSync()) {
    return CheckerResult(
      passed: false,
      detail: 'file not found: $path (agent never wrote it)',
    );
  }
  return fn(file.readAsStringSync());
}
