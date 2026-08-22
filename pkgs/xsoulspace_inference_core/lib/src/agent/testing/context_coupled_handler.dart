// ignore_for_file: lines_longer_than_80_chars

/// Causal task-coupling for harness evaluation (ADR 0004).
///
/// A [ContextCoupledHandler] answers correctly ONLY if the projection
/// contained the beat its decision depended on. If the harness projected the
/// wrong (or no) context, the scripted actor "fails" — making projection
/// quality → task success a deterministic causal chain, still with zero LLM.
///
/// This is the closest measurable proxy for "harness intelligence": how much
/// of scripted-agent success is *caused* by what the harness showed it.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';

import '../events.dart';

/// One dependency: this turn succeeds only if [requiredPhrase] appears in
/// the request's context fragments; otherwise it emits [failureText].
class ContextDependency {
  const ContextDependency({
    required this.requiredPhrase,
    required this.successText,
    required this.failureText,
  });

  /// Text that must appear in the projected context for success.
  final String requiredPhrase;
  final String successText;
  final String failureText;
}

/// A [GenerationHandler] whose responses are causally coupled to what the
/// harness projected. Turns are consumed in order and loop on the last.
class ContextCoupledHandler implements GenerationHandler {
  ContextCoupledHandler(List<ContextDependency> dependencies)
    : dependencies = List.unmodifiable(dependencies);

  final List<ContextDependency> dependencies;
  int _cursor = 0;

  /// One entry per served request: did the harness project the context this
  /// turn's answer depended on?
  final List<bool> contextWasSufficient = [];

  /// Fraction of turns where the projection carried the needed context.
  double get contextSufficiencyRate => contextWasSufficient.isEmpty
      ? 0
      : contextWasSatisfiedCount / contextWasSufficient.length;
  int get contextWasSatisfiedCount =>
      contextWasSufficient.where((ok) => ok).length;

  ContextDependency get _next {
    if (_cursor < dependencies.length) return dependencies[_cursor++];
    return dependencies.isEmpty
        ? const ContextDependency(
            requiredPhrase: '',
            successText: '',
            failureText: '',
          )
        : dependencies.last;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final dep = _next;
    final contextText = request.contextFragments.join(' ');
    final sufficient = dep.requiredPhrase.isEmpty
        ? true
        : contextText.contains(dep.requiredPhrase);
    contextWasSufficient.add(sufficient);

    final text = sufficient ? dep.successText : dep.failureText;
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': text},
      rawOutput: text,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}
