// ignore_for_file: lines_longer_than_80_chars

/// TransformFlow (M2) — the tool-composition ETL layer, built in the
/// DecisionFlow house style:
///
/// | DecisionFlow            | TransformFlow                       |
/// | ----------------------- | ----------------------------------- |
/// | narrow read-only ctx    | [TransformContext] (fs view)        |
/// | pure data draft         | [Op] / [Diagnostic]                 |
/// | combinator DSL          | onFile/onAnchor/when builders       |
/// | named attribution       | every stage outcome carries name    |
/// | mechanical applier      | [applyOps] — the only mutator       |
///
/// Stages *select*; the applier *computes*. Validation runs before any
/// mutation, so a bad anchor or missing file costs zero model calls.
library;

import 'dart:io';

import 'package:meta/meta.dart';

import 'token_estimate.dart' show estimateTokensFromChars;

// ---------------------------------------------------------------------------
// Data shapes
// ---------------------------------------------------------------------------

enum OpKind { patchFile, writeFile }

/// A validated operation emitted by a stage; applied mechanically.
class Op {
  const Op._(this.kind, this.path, {this.body, this.anchor});
  final OpKind kind;
  final String path;
  final String? body;
  final String? anchor;

  int get bodyChars => body?.length ?? 0;

  /// Model-facing token proxy for this op's payload.
  int get tokenCost => estimateTokensFromChars(bodyChars);
}

/// Structured failure — becomes a compact beat, not prose.
@immutable
class Diagnostic {
  const Diagnostic(this.code, {this.path, this.message, this.hint});
  final String code;
  final String? path;
  final String? message;
  final String? hint;

  @override
  String toString() =>
      '[$code${path == null ? '' : ' $path'}] ${message ?? ''}'
      '${hint == null ? '' : ' hint: $hint'}';
}

/// Read-only filesystem view handed to stages.
class TransformContext {
  TransformContext(this.root);
  final String root;

  bool exists(String path) => File(_resolve(path)).existsSync();
  String read(String path) => File(_resolve(path)).readAsStringSync();
  int sizeOf(String path) => exists(path) ? read(path).length : 0;
  int countMatches(String path, String needle) =>
      needle.isEmpty ? 0 : _count(read(path), needle);

  static int _count(String hay, String needle) {
    var n = 0, i = 0;
    while ((i = hay.indexOf(needle, i)) != -1) {
      n++;
      i += needle.length;
    }
    return n;
  }

  String _resolve(String path) => path.startsWith('/') ? path : '$root/$path';
}

sealed class StageResult {
  const StageResult(this.stageName);
  final String stageName;
}

class EmitOp extends StageResult {
  const EmitOp(super.stageName, this.op);
  final Op op;
}

class Fail extends StageResult {
  const Fail(super.stageName, this.diagnostic);
  final Diagnostic diagnostic;
}

class Skip extends StageResult {
  const Skip(super.stageName);
}

typedef _Guard = Diagnostic? Function(TransformContext ctx);
// ---------------------------------------------------------------------------
// Stages & DSL
// ---------------------------------------------------------------------------

abstract class TransformStage {
  String get name;
  StageResult evaluate(TransformContext ctx);
}

/// Guards shared by concrete stages: run in order; first failure wins.
mixin _Guards implements TransformStage {
  final List<_Guard> guards = [];

  StageResult evaluateGuards(TransformContext ctx) {
    for (final g in guards) {
      final d = g(ctx);
      if (d != null) return Fail(name, d);
    }
    return Skip(name);
  }
}

/// `onFile('lib/x.dart').missing('…').thenWrite(body)` — whole-file op.
class FileStage extends TransformStage with _Guards {
  FileStage(this.path, {bool Function(TransformContext)? when})
    : _when = when;
  final String path;
  final bool Function(TransformContext)? _when;
  @override
  String get name => 'file($path)';

  /// Fails when the file does not exist.
  FileStage missing(String code) {
    guards.add((ctx) => ctx.exists(path) ? null : Diagnostic(code, path: path));
    return this;
  }

  /// Fails when current file content exceeds [bytes].
  FileStage largerThan(int bytes, String code) {
    guards.add(
      (ctx) => !ctx.exists(path) || ctx.sizeOf(path) > bytes
          ? Diagnostic(code, path: path)
          : null,
    );
    return this;
  }

  Op? _op;

  FileStage thenWrite(String body) {
    _op = Op._(OpKind.writeFile, path, body: body);
    return this;
  }

  @override
  StageResult evaluate(TransformContext ctx) {
    final when = _when;
    if (when != null && !when(ctx)) return Skip(name);
    final r = evaluateGuards(ctx);
    if (r is Fail) return r;
    final op = _op;
    if (op == null) return Skip(name);
    return EmitOp(name, op);
  }
}

/// `onAnchor(path, snippet).notUnique().thenReplace(newText)` — validate the
/// exact-match span first; only a unique anchor produces a patch op.
class AnchorStage extends TransformStage with _Guards {
  AnchorStage(this.path, this.anchor);
  final String path;
  final String anchor;

  @override
  String get name => 'anchor($path #${anchor.length}b)';

  AnchorStage fileMissing(String code) {
    guards.add((ctx) => ctx.exists(path) ? null : Diagnostic(code, path: path));
    return this;
  }

  AnchorStage notUnique(String code) {
    guards.add((ctx) {
      final n = ctx.countMatches(path, anchor);
      return n == 1
          ? null
          : Diagnostic(code, path: path, message: 'matches=$n',
              hint: 'anchor must match exactly once');
    });
    return this;
  }

  Op? _op;

  AnchorStage thenReplace(String newText) {
    _op = Op._(OpKind.patchFile, path, body: newText, anchor: anchor);
    return this;
  }

  @override
  StageResult evaluate(TransformContext ctx) {
    final r = evaluateGuards(ctx);
    if (r is Fail) return r;
    final op = _op;
    if (op == null) return Skip(name);
    return EmitOp(name, op);
  }
}



/// `when(cond, label: …).then([...stages])` gate.
class WhenStage extends TransformStage {
  WhenStage(this.cond, {required this.label});
  final bool Function(TransformContext) cond;
  final String label;
  final stages = <TransformStage>[];

  WhenStage then(List<TransformStage> children) {
    stages.addAll(children);
    return this;
  }

  @override
  String get name => 'when($label)';

  @override
  StageResult evaluate(TransformContext ctx) {
    if (!cond(ctx)) return Skip(name);
    for (final st in stages) {
      final r = st.evaluate(ctx);
      if (r is! Skip) return r;
    }
    return Skip(name);
  }
}

class TransformFlow {
  TransformFlow(this.stages);
  final List<TransformStage> stages;

  /// Evaluate all stages against [ctx]; returns named outcomes. Never
  /// mutates anything.
  List<StageResult> evaluate(TransformContext ctx) =>
      [for (final s in stages) s.evaluate(ctx)];
}

class ApplyReport {
  int applied = 0;
  int failed = 0;
  int tokenCost = 0;
  final diagnostics = <Diagnostic>[];

  @override
  String toString() =>
      'applied=$applied failed=$failed tokenCost=$tokenCost '
      'diagnostics=${diagnostics.map((d) => d.toString()).join('; ')}';
}

/// The ONLY mutator: applies validated [EmitOp] results to disk under
/// [root]. Patch semantics = exact-match anchor replacement, count==1.
ApplyReport applyOps(String root, List<StageResult> results) {
  final report = ApplyReport();
  final ctx = TransformContext(root);
  for (final r in results) {
    if (r is Fail) {
      report.failed++;
      report.diagnostics.add(r.diagnostic);
      continue;
    }
    if (r is! EmitOp) continue;
    final op = r.op;
    switch (op.kind) {
      case OpKind.writeFile:
        final f = File('${ctx.root}/${op.path}')
          ..createSync(recursive: true);
        f.writeAsStringSync(op.body ?? '');
        report.applied++;
        report.tokenCost += op.tokenCost;
      case OpKind.patchFile:
        final file = File('${ctx.root}/${op.path}');
        final src = file.readAsStringSync();
        final matches =
            op.anchor!.isEmpty ? 0 : TransformContext._count(src, op.anchor!);
        if (matches != 1) {
          report.failed++;
          report.diagnostics.add(
            Diagnostic(
              'anchor_not_unique',
              path: op.path,
              message: 'matches=$matches',
              hint: 're-run flow to re-validate before patching',
            ),
          );
          continue;
        }
        file.writeAsStringSync(src.replaceFirst(op.anchor!, op.body ?? ''));
        report.applied++;
        report.tokenCost += op.tokenCost;
    }
  }
  return report;
}
