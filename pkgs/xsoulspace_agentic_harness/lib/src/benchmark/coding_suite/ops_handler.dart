// ignore_for_file: lines_longer_than_80_chars

/// Ops-arm scripted handler: emits a single `patch_file` call whose payload
/// is the replacement fragment only — the model-facing shape we claim cuts
/// generated tokens on the edit path.
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';


/// Per-task canned patch ops for the ops arm (family under measurement).
final Map<String, List<Map<String, dynamic>>> opsBehaviors = {
  'refactor_patch_01': [
    {
      'path': 'lib/pricing.dart',
      'anchor': '    return sum * (1 + tax);',
      'new_text': '    return (sum + processingFee) * (1 + tax);',
    },
  ],
};

class OpsSuiteHandler implements GenerationHandler {
  OpsSuiteHandler({required this.taskId});
  final String taskId;
  bool _emitted = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final ops = opsBehaviors[taskId];
    if (ops == null || _emitted) {
      final done = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'done'},
        rawOutput: 'done',
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(done);
      return done;
    }
    _emitted = true;
    final op = ops.single;
    final raw = 'patch ${op['path']}';
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': raw},
      rawOutput: raw,
      toolCalls: [ToolCall(name: const ToolName('patch_file'), arguments: op)],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Baseline-arm handler for the same family: rewrites the WHOLE file
/// (today's default edit path) — identical end state, maximal payload.
class WholeFileSuiteHandler implements GenerationHandler {
  WholeFileSuiteHandler({required this.taskId});
  final String taskId;
  bool _emitted = false;

  static const _wholeFile = '''
class Pricing {
  double total(List<double> items, {double tax = 0.19, double processingFee = 0}) {
    var sum = 0.0;
    for (final i in items) {
      sum += i;
    }
    return (sum + processingFee) * (1 + tax);
  }

  double discounted(double value, double pct) => value * (1 - pct);
}
''';

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (_emitted) {
      final done = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'done'},
        rawOutput: 'done',
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(done);
      return done;
    }
    _emitted = true;
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'write'},
      rawOutput: 'write lib/pricing.dart',
      toolCalls: [
        ToolCall(name: const ToolName('write'), arguments: {
          'path': 'lib/pricing.dart',
          'content': _wholeFile,
        }),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}
