// ignore_for_file: lines_longer_as_80_chars

/// ADR 0030 — one decision, one program: the model-emitted READ chain.
///
/// A decision may emit ONE `meaning_program` call whose `ops` argument is
/// a program over a CLOSED READ op set — `locate`, `zoom`, `impact`,
/// `read` — interpreted here against the meaning tree. The fixed surface
/// is paid ONCE for N reads; the contract (ADR 0028) holds by
/// construction: one call, one result, nothing accumulates natively.
///
/// **The format is never the model's choice.** Ops address MEANING NODES,
/// never files or languages: the node's class routes the host's span
/// reader (ADR 0024 `file_class_spec`) — a section reads as md, a keypath
/// as yaml/json, a symbol as a Dart span, through the SAME `read` op. New
/// languages/frameworks grow the registry, never this surface.
///
/// **Cursor law.** `locate` SETS the cursor (its ranked hit ids, capped);
/// `zoom`/`impact`/`read` consume `cursor.first` unless an explicit
/// `focusId` overrides. That is the whole dataflow — no names, no JSON
/// paths, nothing a tiny model cannot hold.
///
/// **Result-cut law** (from `execution_meaning`): per-op results are
/// bounded at the interpreter (an over-budget result is replaced by a
/// named clip marker — re-read narrowly), the verdict is bounded by
/// `budget`, and early stop names truncation honestly. Fail-fast: an
/// invalid op halts the program with a named bounce (index, op, error,
/// hint) — later ops never run.
///
/// GATED (ADR 0030 §3): this tool does NOT enter the meaning profile
/// while the fixed-surface gate is saturated (1,598/1,600). It graduates
/// ONLY BY REPLACING the verbs it subsumes — the profile shrinks, never
/// grows.
///
/// **Mutation and effects join as HOST-REGISTERED ops** ([hostOps], the
/// ADR 0015/0022 effects-as-data pattern): the core stays read-only and
/// domain-generic; a host (workspace, daemon) registers jailed effect ops
/// — an `edit` backed by edit_symbol, a `write_review` backed by the
/// consent gateway — as ordinary [ToolDef]s. Registered ops obey the SAME
/// laws as the built-ins: fail-fast with named bounces, result-cut, one
/// call per decision; jailing and consent stay with the registering host.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import '../tools/meaning_locate_tool.dart';
import '../tools/meaning_query_tools.dart'
    show MeaningSpanReader, meaningImpactTool, meaningZoomTool;

/// The closed READ op set (ADR 0030 §1). Mutation ops join ONLY behind a
/// verified on-device row.
const meaningReadProgramOps = <String>['locate', 'zoom', 'impact', 'read'];

/// Deterministic program bound — no jumps, but a runaway program is still
/// a bounded artifact.
const programMaxOps = 8;

/// Per-op result budget (est tokens, chars/4 — the harness estimator).
/// An over-budget result is CLIPPED to a named marker, never inlined.
const perOpResultBudgetTokens = 512;

/// Default verdict budget (est tokens) across the whole program envelope.
const defaultProgramVerdictBudgetTokens = 1200;

/// Cursor cap — locate may find 128 rows; the cursor keeps the sharpest.
const programCursorCap = 8;

int _estTokens(Object? o) => ('${o ?? ''}'.length / 4).ceil();

ToolDef meaningProgramTool(
  World world, {
  MeaningSpanReader? spanReader,
  Map<String, ToolDef> hostOps = const {},
}) {
  // The program interpreter CALLS the existing tool implementations —
  // ranking, budget shrink-loops and repair hints are inherited, never
  // reimplemented (composition, not a second pipeline).
  final locate = meaningLocateTool(world);
  final zoom = meaningZoomTool(world, spanReader: spanReader);
  final impact = meaningImpactTool(world);

  Future<Map<String, dynamic>> runOp(
    Map<String, dynamic> args,
  ) async {
    final opName = args['op'] as String?;
    // Host-registered effect ops first (ADR 0015/0022): the host owns
    // jailing, consent and verification — the runner only owns the laws.
    final hostOp = hostOps[opName];
    if (hostOp != null) {
      final out = await hostOp.execute(args);
      return jsonDecode(out ?? '{}') as Map<String, dynamic>;
    }
    final raw = switch (opName) {
      // `read` IS a point zoom (ADR 0030 §2): the node's class routes the
      // host span reader — md section, yaml keypath or Dart span — and the
      // op never names a format.
      'locate' => locate.execute(args),
      'zoom' => zoom.execute(args),
      'impact' => impact.execute(args),
      'read' => zoom.execute({
        ...args,
        'zoom': 'point',
        'budget': args['budget'] is int ? args['budget'] as int : 512,
      }),
      _ => null,
    };
    final out = await raw;
    return jsonDecode(out ?? '{}') as Map<String, dynamic>;
  }

  return ToolDef.encode(
    name: const ToolName('meaning_program'),
    description:
        'Run a READ program over the meaning tree in ONE call: '
        'ops = [locate, zoom, impact, read]. locate SETS the cursor (its '
        'hit ids); zoom/impact/read consume cursor.first unless focusId '
        'overrides. You never name a file language — a node reads as '
        'code, md section or yaml key through its OWN class. Fail-fast: '
        'an invalid op halts with a named bounce. Per-op results and '
        'the verdict are budget-clipped honestly.',
    argsSchema: SchemaBundle(
      root: FM.object(
        'meaning_program',
        properties: () => [
          FM.prop(
            'ops',
            FM.array(
              FM.object(
                'op',
                properties: () => [
                  FM.prop('op', FM.string()),
                  FM.prop('query', FM.string(), optional: true),
                  FM.prop('focusId', FM.string(), optional: true),
                  FM.prop('budget', FM.integer(), optional: true),
                ],
              ),
            ),
          ),
          FM.prop('budget', FM.integer(), optional: true),
        ],
      ),
    ),
    execute: (args) async {
      final map = args is Map ? args : const <String, dynamic>{};
      final opsRaw = map['ops'];
      if (opsRaw is! List || opsRaw.isEmpty) {
        return {
          'ok': false,
          'program_halt': {
            'index': 0,
            'error': 'ops_required',
            'hint': 'ops is a non-empty array of {op: locate|zoom|impact|read}',
          },
        };
      }
      if (opsRaw.length > programMaxOps) {
        return {
          'ok': false,
          'program_halt': {
            'index': 0,
            'error': 'too_many_ops: ${opsRaw.length} > $programMaxOps',
            'hint': 'split the work across decisions — the next decision '
                'sees this verdict',
          },
        };
      }
      final verdictBudget = map['budget'] is int && (map['budget'] as int) > 0
          ? map['budget'] as int
          : defaultProgramVerdictBudgetTokens;

      final cursor = <String>[];
      final results = <Map<String, dynamic>>[];
      var truncated = false;

      for (var i = 0; i < opsRaw.length; i++) {
        final opArgs = opsRaw[i];
        if (opArgs is! Map) {
          return _halt(i, '?', 'op_not_an_object', results, cursor);
        }
        final spec = Map<String, dynamic>.from(opArgs);
        final op = spec['op'];
        final knownOp = op is String &&
            (meaningReadProgramOps.contains(op) || hostOps.containsKey(op));
        if (!knownOp) {
          final registered = hostOps.isEmpty
              ? ''
              : ' + registered: ${hostOps.keys.toList()}';
          return _halt(
            i,
            '$op',
            'unknown_op — closed set: $meaningReadProgramOps$registered',
            results,
            cursor,
          );
        }

        // Cursor law: BUILT-IN reads consume cursor.first unless focusId
        // overrides. Host-registered ops define their own args — the focus
        // requirement does not apply to them.
        if (op != 'locate' &&
            !hostOps.containsKey(op) &&
            spec['focusId'] == null &&
            cursor.isNotEmpty) {
          spec['focusId'] = cursor.first;
        }
        if (op != 'locate' &&
            !hostOps.containsKey(op) &&
            spec['focusId'] == null) {
          return _halt(
            i,
            op,
            'no_focus — run locate first (it sets the cursor) or pass '
                'focusId',
            results,
            cursor,
          );
        }

        final out = await runOp(spec);

        // Fail-fast: an op that came back with a named tool error halts the
        // program — later ops would read a stale cursor. The bounce carries
        // the tool's own repair hints (unknown-focusId suggestions etc.).
        if (out['ok'] != true && out.containsKey('error')) {
          return _halt(i, op, '${out['error']}', results, cursor);
        }

        // locate advances the cursor (sharpest hits first, capped).
        if (op == 'locate' && out['ok'] == true) {
          final rows = out['rows'];
          if (rows is List) {
            cursor
              ..clear()
              ..addAll([
                for (final r in rows.take(programCursorCap))
                  if (r is Map && r['id'] is String) r['id'] as String,
              ]);
          }
        }

        // Result-cut law: an over-budget op result is CLIPPED to a named
        // marker — the model re-reads narrowly, the verdict stays small.
        if (_estTokens(out) > perOpResultBudgetTokens) {
          results.add({
            'op': op,
            'clipped': true,
            'est_tokens': _estTokens(out),
            'hint': 'result exceeded the per-op budget — repeat this op '
                'with a smaller budget/maxNodes or a sharper focusId',
          });
        } else {
          results.add({op: out});
        }

        // Verdict budget: early stop, named honestly. Later ops never run.
        if (_estTokens(results) > verdictBudget && i < opsRaw.length - 1) {
          truncated = true;
          results.add({
            'truncated': true,
            'hint': 'verdict budget reached at op ${i + 1} of '
                '${opsRaw.length} — the remaining ops were NOT run; send a '
                'narrower program in the next decision',
          });
          break;
        }
      }

      return {
        'ok': true,
        'ops_run': results.length,
        if (truncated) 'truncated': true,
        'results': results,
        if (cursor.isNotEmpty) 'cursor': cursor,
      };
    },
  );
}

Map<String, dynamic> _halt(
  int index,
  String op,
  String error,
  List<Map<String, dynamic>> results,
  List<String> cursor,
) => {
  'ok': false,
  'program_halt': {
    'index': index,
    'op': op,
    'error': error,
    'hint': 'fix op $index and resend the program — the next decision '
        'sees this verdict and the results-so-far',
  },
  'ops_run': results.length,
  'results': results,
  if (cursor.isNotEmpty) 'cursor': cursor,
};
