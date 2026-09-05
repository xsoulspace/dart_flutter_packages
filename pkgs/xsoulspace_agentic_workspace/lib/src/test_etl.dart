// ignore_for_file: lines_longer_than_80_chars

/// ETL-in — the workspace oracle becomes the intent expectation table.
///
/// ADR 0022 §1: the workspace's OWN test suite IS the oracle. This module is
/// a pure, deterministic, LLM-free host program:
///
/// 1. scan every `test/**/*_test.dart` for
///    `expect(subjectFn(<literals>), <literal | equals(lit) | isTrue | isFalse>)`;
/// 2. read each subject's top-level signature from `lib/**.dart`;
/// 3. emit [DerivedIntent] skeletons whose expectations cite the exact test
///    lines they came from (`provenance`).
///
/// NOTHING here is hand-authored — the R6/A-closure fix. Extraction is
/// structural (balanced-paren scanning + top-level declaration regexes),
/// deliberately NOT an analyzer resolution pass: the analyzer round-trip is
/// the P4 span-edit path; this derivation only needs the v1 shape (top-level
/// functions, required positional params, literal call args). Shapes outside
/// the scope come back as honest `unresolved` rows — never silently dropped
/// (standing rule 4).
///
/// Broader wire evolution (machine test output, multi-framework) is AE's
/// `test_wire` contract:
/// `~/xs/agentic_executables/docs/ae_harness_etl_spec.md`.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show IntentExpectation;

/// One derived param: `name:type` (the model's intent_define vocabulary).
typedef DartParam = ({String name, String type});

/// One intent skeleton derived from the workspace suite — AE canonical-row
/// material (ADR 0022: expectations are DERIVED, never authored).
class DerivedIntent {
  DerivedIntent({
    required this.intent,
    required this.targetFile,
    required this.params,
    required this.returns,
    required this.expectations,
    required this.provenance,
  });

  /// The Dart function name under test (also the intent name).
  final String intent;

  /// Workspace-relative file declaring the subject — the materializer's
  /// write target.
  final String targetFile;

  final List<DartParam> params;
  final String returns;

  /// Derived from the suite's expect() calls, in source order.
  final List<IntentExpectation> expectations;

  /// `file:line` of every test call the expectations came from.
  final List<String> provenance;
}

/// The ETL product: derivable skeletons + honest unresolved rows.
class WorkspaceDerivation {
  WorkspaceDerivation({required this.intents, required this.unresolved});

  final List<DerivedIntent> intents;

  /// Rows that could not be derived — classified data, never dropped.
  final List<String> unresolved;

  bool get isEmpty => intents.isEmpty;
}

/// Extracts the first balanced `expect(...)` group starting at [start].
/// Returns the inner text (between the outer parens) and the index after
/// the closing paren.
(String, int)? _balanced(String s, int start) {
  var depth = 0;
  var inStr = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (c == r'\') {
        i++;
      } else if (c == "'") {
        inStr = false;
      }
      continue;
    }
    if (c == "'") {
      inStr = true;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return (s.substring(start + 1, i), i + 1);
    }
  }
  return null;
}

/// Splits [s] on top-level commas (parens, brackets, strings respected).
List<String> _topLevelSplit(String s) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var inStr = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      buf.write(c);
      if (c == r'\') {
        i++;
        if (i < s.length) buf.write(s[i]);
      } else if (c == "'") {
        inStr = false;
      }
      continue;
    }
    if (c == "'") {
      inStr = true;
      buf.write(c);
    } else if (c == '(' || c == '[') {
      depth++;
      buf.write(c);
    } else if (c == ')' || c == ']') {
      depth--;
      buf.write(c);
    } else if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  if (buf.toString().trim().isNotEmpty) parts.add(buf.toString().trim());
  return parts;
}

/// Parses a literal argument: int/double/negative/bool/null/string/list.
(Object?, bool) _literalOf(String raw) {
  final t = raw.trim();
  if (t == 'null') return (null, true);
  if (t == 'true') return (true, true);
  if (t == 'false') return (false, true);
  final n = num.tryParse(t);
  if (n != null) return (n, true);
  if (t.length >= 2 && t.startsWith("'") && t.endsWith("'")) {
    final inner = t
        .substring(1, t.length - 1)
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', r'\');
    return (inner, true);
  }
  if (t.startsWith('[') && t.endsWith(']')) {
    final inner = t.substring(1, t.length - 1).trim();
    if (inner.isEmpty) return (<dynamic>[], true);
    final out = <dynamic>[];
    for (final el in _topLevelSplit(inner)) {
      final (v, ok) = _literalOf(el);
      if (!ok) return (null, false);
      out.add(v);
    }
    return (out, true);
  }
  return (null, false);
}


/// Infers a Dart type from a derived literal value (greenfield tasks have
/// no declared signature — the suite's own literals are the only honest
/// evidence). Returns null when the value carries no inferable type.
String? _inferType(Object? v) {
  if (v is int) return 'int';
  if (v is double) return 'double';
  if (v is String) return 'String';
  if (v is bool) return 'bool';
  if (v is List) {
    if (v.isEmpty) return 'List<dynamic>';
    final elemTypes = [
      for (final e in v) _inferType(e),
    ];
    if (elemTypes.every((t) => t == elemTypes.first && t != null)) {
      return 'List<${elemTypes.first}>';
    }
    return 'List<dynamic>';
  }
  return null;
}

/// The workspace's package name from pubspec.yaml (for package: import
/// resolution), or null.
String? _pubspecName(Directory workspace) {
  final f = File('${workspace.path}/pubspec.yaml');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^name:\s*([\w-]+)\s*$').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

/// The lib-relative file a test file's `package:<name>/<rel>.dart` import
/// points at — the suite itself declares where the subject lives (D8).
List<String> _importedLibFiles(String testSrc, String pkgName) {
  final out = <String>[];
  final re = RegExp(
    "import\\s+'package:$pkgName/([^']+)'\\s*;",
  );
  for (final m in re.allMatches(testSrc)) {
    out.add(m.group(1)!);
  }
  return out;
}

/// Extracts the expected value from the matcher expression.
(Object?, String?) _expectedOf(String raw) {
  final t = raw.trim();
  if (t == 'isTrue') return (true, null);
  if (t == 'isFalse') return (false, null);
  final eq = RegExp(r'^equals\s*\((.*)\)\s*$', dotAll: true).firstMatch(t);
  if (eq != null) {
    final (v, ok) = _literalOf(eq.group(1)!);
    return (v, ok ? null : 'unsupported equals() argument: ${eq.group(1)}');
  }
  final (v, ok) = _literalOf(t);
  return (v, ok ? null : 'unsupported matcher: $t');
}

class _TestRow {
  _TestRow(this.subject, this.args, this.expected, this.line, this.file);
  final String subject;
  final List<Object?> args;
  final (Object?, String?) expected;
  final int line;
  final String file;
}

List<_TestRow> _rowsFromTestFile(File f) {
  final src = f.readAsStringSync();
  final rows = <_TestRow>[];
  var searchFrom = 0;
  while (true) {
    final idx = src.indexOf('expect(', searchFrom);
    if (idx == -1) break;
    searchFrom = idx + 1;
    // expect( starts at idx; the balanced group starts at idx + 6.
    final inner = _balanced(src, idx + 6);
    if (inner == null) continue;
    final (body, end) = inner;
    searchFrom = end;
    final parts = _topLevelSplit(body);
    if (parts.length != 2) continue; // reason: strings etc. — v1 skip
    final m = _parseCall(parts[0].trim());
    if (m == null) continue;
    final line = '\n'.allMatches(src.substring(0, idx)).length + 1;
    rows.add(_TestRow(m.subject, m.args, _expectedOf(parts[1]), line, f.path));
  }
  return rows;
}

({String subject, List<Object?> args})? _parseCall(String call) {
  final open = call.indexOf('(');
  if (open <= 0 || !call.endsWith(')')) return null;
  final subject = call.substring(0, open).trim();
  if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(subject)) return null;
  final inner = call.substring(open + 1, call.length - 1);
  final args = <Object?>[];
  for (final a in _topLevelSplit(inner)) {
    final (v, ok) = _literalOf(a);
    if (!ok) return null;
    args.add(v);
  }
  return (subject: subject, args: args);
}

/// Top-level function signatures in one lib file:
/// `ReturnType name(Type a, Type b) {` or `=> ...;` at indentation 0.
class _FnSig {
  _FnSig(this.name, this.returnType, this.params);
  final String name;
  final String returnType;
  final List<DartParam> params;
}

List<_FnSig> _signaturesOf(File f) {
  final sigs = <_FnSig>[];
  final lines = f.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
      continue; // top-level only (v1 scope)
    }
    final m = RegExp(
      r'^([A-Za-z_][\w<>, ?]*)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(\{|=>)',
    ).firstMatch(line);
    if (m == null) continue;
    final params = <DartParam>[];
    var ok = true;
    final rawParams = m.group(3)!.trim();
    if (rawParams.isNotEmpty) {
      for (final p in _topLevelSplit(rawParams)) {
        final pm = RegExp(r'^([\w<>, ?]+?)\s+([A-Za-z_]\w*)$').firstMatch(
          p.trim(),
        );
        if (pm == null) {
          ok = false;
          break;
        }
        params.add((name: pm.group(2)!, type: pm.group(1)!.trim()));
      }
    }
    if (!ok) continue;
    sigs.add(_FnSig(m.group(2)!, m.group(1)!.trim(), params));
  }
  return sigs;
}

/// Derives intent skeletons from the workspace's own test suite.
///
/// Throws only when the workspace carries no test suite at all (the host
/// must fail honestly — never invent a criterion the workspace does not
/// declare, D8/M0).
WorkspaceDerivation deriveWorkspaceIntents(Directory workspace) {
  final testDir = Directory('${workspace.path}/test');
  if (!testDir.existsSync()) {
    throw StateError(
      'workspace-oracle ETL: ${workspace.path} has no test/ directory — '
      'no criterion resolvable (D8/M0).',
    );
  }
  final libDir = Directory('${workspace.path}/lib');
  final sigs = <String, (String, _FnSig)>{};
  if (libDir.existsSync()) {
    for (final f in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final sig in _signaturesOf(f)) {
        sigs.putIfAbsent(sig.name, () => (f.path, sig));
      }
    }
  }
  final rows = <_TestRow>[];
  final unresolved = <String>[];
  for (final f in testDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('_test.dart'))) {
    rows.addAll(_rowsFromTestFile(f));
  }
  final bySubject = <String, List<_TestRow>>{};
  for (final r in rows) {
    bySubject.putIfAbsent(r.subject, () => []).add(r);
  }
  String relOf(String abs) => abs.startsWith('${workspace.path}/')
      ? abs.substring(workspace.path.length + 1)
      : abs;

  final intents = <DerivedIntent>[];
  for (final subject in bySubject.keys.toList()..sort()) {
    final rowsFor = bySubject[subject]!;
    final found = sigs[subject];

    if (found == null) {
      // ── Greenfield subject ────────────────────────────────────────────
      // No declaration exists yet: the suite is the whole spec. The target
      // file comes from the test's own package import (D8: the workspace
      // declares where the subject lives); types are inferred from the
      // suite's derived literals (documented inference, not magic).
      final pkg = _pubspecName(workspace);
      final imports = <String>{};
      if (pkg != null) {
        for (final r in rowsFor) {
          imports.addAll(
            _importedLibFiles(File(r.file).readAsStringSync(), pkg),
          );
        }
      }
      if (imports.length != 1) {
        unresolved.add(
          'subject "$subject" declared in no lib/ file and the suite does '
          'not declare exactly one package import (found: ${imports.length}) '
          '— cannot place the materialized implementation',
        );
        continue;
      }
      final target = 'lib/${imports.single}';
      final params = <DartParam>[];
      final expectations = <IntentExpectation>[];
      final provenance = <String>[];
      // Param types inferred from the FIRST fully-literal call.
      final first = rowsFor.first;
      var paramsOk = true;
      for (final (i, a) in first.args.indexed) {
        final t = _inferType(a);
        if (t == null) {
          unresolved.add(
            '$subject (line ${first.line}): arg $i has no inferable type',
          );
          paramsOk = false;
          break;
        }
        params.add((name: 'arg$i', type: t));
      }
      if (!paramsOk) continue;
      var anyExpectation = false;
      for (final r in rowsFor) {
        final (expected, why) = r.expected;
        if (why != null && why.isNotEmpty) {
          unresolved.add('$subject (line ${r.line}): $why');
          continue;
        }
        if (r.args.length != params.length) {
          unresolved.add(
            '$subject (line ${r.line}): ${r.args.length} call args vs '
            '${params.length} inferred params — arity mismatch',
          );
          continue;
        }
        expectations.add(
          IntentExpectation(
            subject,
            args: {
              for (final (i, p) in params.indexed) p.name: r.args[i],
            },
            expect: {'value': expected},
          ),
        );
        provenance.add('${relOf(r.file)}:${r.line}');
        anyExpectation = true;
      }
      if (!anyExpectation) {
        unresolved.add('$subject: no derivable expectations');
        continue;
      }
      intents.add(
        DerivedIntent(
          intent: subject,
          targetFile: target,
          params: params,
          returns: _inferType(expectations.first.expect['value']) ?? 'dynamic',
          expectations: expectations,
          provenance: provenance,
        ),
      );
      continue;
    }

    // ── Declared subject ────────────────────────────────────────────────
    final (file, sig) = found;
    final expectations = <IntentExpectation>[];
    final provenance = <String>[];
    for (final r in rowsFor) {
      final (expected, why) = r.expected;
      if (why != null && why.isNotEmpty) {
        unresolved.add('$subject (line ${r.line}): $why');
        continue;
      }
      if (r.args.length != sig.params.length) {
        unresolved.add(
          '$subject (line ${r.line}): ${r.args.length} call args vs '
          '${sig.params.length} declared params — arity mismatch',
        );
        continue;
      }
      expectations.add(
        IntentExpectation(
          subject,
          args: {
            for (final (i, p) in sig.params.indexed) p.name: r.args[i],
          },
          expect: {'value': expected},
        ),
      );
      provenance.add('${relOf(r.file)}:${r.line}');
    }
    if (expectations.isEmpty) {
      unresolved.add('$subject: no derivable expectations');
      continue;
    }
    intents.add(
      DerivedIntent(
        intent: subject,
        targetFile: relOf(file),
        params: sig.params,
        returns: sig.returnType,
        expectations: expectations,
        provenance: provenance,
      ),
    );
  }
  return WorkspaceDerivation(intents: intents, unresolved: unresolved);
}