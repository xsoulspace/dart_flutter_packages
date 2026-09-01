// ignore_for_file: lines_longer_than_80_chars

/// Attribution ledger (M1): per-decision accounting of where the budget
/// actually goes — prompt bytes by fragment class, generated size, model
/// wall time, and outcome class — so optimization targets are ranked by
/// measurement instead of intuition.
///
/// Composition style matches [DecisionFlow]: narrow inputs, pure data rows,
/// named outcomes; the ledger never mutates the world.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../events.dart';

/// One decision's attribution row.
class DecisionAttribution {
  const DecisionAttribution({
    required this.seq,
    required this.agentId,
    required this.systemBytes,
    required this.promptBytes,
    required this.contextBytes,
    required this.generatedChars,
    required this.modelMs,
    required this.outcome,
    required this.retries,
    this.taskId,
  });

  final int seq;
  final String agentId;

  /// System prompt size (identity/instructions).
  final int systemBytes;

  /// The decision prompt itself.
  final int promptBytes;

  /// Projected context bytes by fragment class.
  final Map<String, int> contextBytes;

  /// Characters the backend produced (token proxy — see token_estimate).
  final int generatedChars;

  /// Wall time spent inside the backend handler.
  final int modelMs;
  final String outcome;
  final int retries;
  final Object? taskId;
}

/// Append-only ledger resource; cheap enough to always attach.
class AttributionLedger extends Resource {
  final rows = <DecisionAttribution>[];
  int _seq = 0;

  void record(DecisionAttribution row) => rows.add(row);

  int get nextSeq => _seq++;

  /// Aggregated rollup per outcome class and fragment bucket.
  Map<String, Object?> summarize() {
    var sys = 0;
    var prompt = 0;
    var gen = 0;
    var ms = 0;
    final ctx = <String, int>{};
    final outcomes = <String, int>{};
    for (final r in rows) {
      sys += r.systemBytes;
      prompt += r.promptBytes;
      gen += r.generatedChars;
      ms += r.modelMs;
      r.contextBytes.forEach((k, v) => ctx[k] = (ctx[k] ?? 0) + v);
      outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;
    }
    return {
      'decisions': rows.length,
      'systemBytes': sys,
      'promptBytes': prompt,
      'generatedChars': gen,
      'modelMs': ms,
      'contextBytes': ctx,
      'outcomes': outcomes,
    };
  }

  /// Ranked worst-part table: biggest budget consumers first.
  String report() {
    final s = summarize();
    final ctx = (s['contextBytes']! as Map<String, int>)
        .entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final buf = StringBuffer()
      ..writeln('== attribution ==')
      ..writeln('decisions: ${s['decisions']}')
      ..writeln(
        'bytes: system=${s['systemBytes']} prompt=${s['promptBytes']} '
        'generated=${s['generatedChars']} modelMs=${s['modelMs']}',
      )
      ..writeln('context buckets (desc):');
    for (final e in ctx) {
      buf.writeln('  ${e.key}: ${e.value}');
    }
    buf.writeln('outcomes: ${s['outcomes']}');
    return buf.toString();
  }
}

/// Verbose tap for debugging real-model runs.
bool attributionDebug = false;

/// Decorator that attributes every decision passing through a handler.
///
/// Wraps any backend (scripted, OpenRouter, AFM FFI) identically — the
/// provider seam stays untouched.
class AttributedHandler implements GenerationHandler {
  AttributedHandler(this.inner, this.ledger);
  final GenerationHandler inner;
  final AttributionLedger ledger;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final sw = Stopwatch()..start();
    final response = await inner.generate(world, request);
    sw.stop();

    final contextBytes = <String, int>{'context': 0};
    for (final f in request.contextFragments) {
      final text = '$f';
      final key = _classify(text);
      contextBytes[key] = (contextBytes[key] ?? 0) + text.length;
    }
    final retries =
        world.getEntity(request.actorEntity).$1.get<RetryCount>()?.value ?? 0;
    // Bits out of the model = visible text AND tool-call arguments (a
    // whole-file write hides most of its payload in arguments).
    var outChars = response.rawOutput.length;
    for (final call in response.toolCalls) {
      outChars += call.arguments.toString().length;
    }
    final r = DecisionAttribution(
      seq: ledger.nextSeq,
      agentId: request.agentId.value,
      systemBytes: request.systemPrompt.length,
      promptBytes: request.prompt.length,
      contextBytes: contextBytes,
      generatedChars: outChars,
      modelMs: sw.elapsedMilliseconds,
      outcome: response.error.isNotEmpty
          ? 'error'
          : response.toolCalls.isNotEmpty
              ? 'acted'
              : 'answered',
      retries: retries,
      taskId: request.taskId,
    );
    ledger.record(r);
    if (attributionDebug) {
      final names = response.toolCalls
          .map((c) => '${c.name.value}(${c.arguments})')
          .join('; ');
      // ignore: avoid_print
      stdout.writeln(
        '[dec#${r.seq}] ${r.outcome} tools=[$names] '
        'raw=${_clip(response.rawOutput)} err=${response.error}',
      );
    }
    return response;
  }

  static String _clip(String s, [int n = 140]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  static String _classify(String fragment) {
    if (fragment.startsWith(ContextFragmentProtocol.assistantPrefix)) {
      return 'assistant';
    }
    if (fragment.startsWith(ContextFragmentProtocol.toolResultPrefix)) {
      return 'tool';
    }
    if (fragment.startsWith(ContextFragmentProtocol.absencePrefix)) {
      return 'absence';
    }
    return 'context';
  }
}
