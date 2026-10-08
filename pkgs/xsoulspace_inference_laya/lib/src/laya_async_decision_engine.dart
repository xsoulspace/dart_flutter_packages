import 'dart:async';
import 'dart:collection';

import 'package:async_parallel/async_parallel.dart';

import 'laya_decision_server.dart';
import 'laya_native_decision_engine.dart';

/// One physical model shared by independent logical callers. Admission is
/// bounded and FIFO; an abandoned HTTP request does not release capacity while
/// native inference still runs. No actor context is retained between jobs.
///
/// Uses ecsly's framework-independent executor seam, not a second world loop.
/// Native load and inference run outside the owner's isolate. The model handle
/// remains process-owned and is unloaded only after the actual queue drains.
final class AsyncLayaDecisionEngine implements CalibratedLayaDecisionEngine {
  AsyncLayaDecisionEngine({
    required CalibratedLayaDecisionEngine engine,
    this.executor = defaultIsolateExecutor,
    this.maxPending = 32,
    FutureOr<void> Function()? disposeEngine,
    // Public composition parameters intentionally do not expose private fields.
    // ignore: prefer_initializing_formals
  }) : _engine = engine,
       // ignore: prefer_initializing_formals
       _disposeEngine = disposeEngine {
    if (maxPending < 1) throw ArgumentError.value(maxPending, 'maxPending');
  }

  static Future<AsyncLayaDecisionEngine> loadNative({
    String? modelDir,
    IsolateExecutor executor = defaultIsolateExecutor,
    int maxPending = 32,
  }) async {
    final engine = await executor.compute(_loadNative, modelDir);
    return AsyncLayaDecisionEngine(
      engine: engine,
      executor: executor,
      maxPending: maxPending,
      disposeEngine: engine.dispose,
    );
  }

  final CalibratedLayaDecisionEngine _engine;
  final FutureOr<void> Function()? _disposeEngine;
  final IsolateExecutor executor;
  final int maxPending;
  final Queue<_Job> _queue = Queue<_Job>();
  bool _running = false;
  bool _closed = false;
  Future<void>? _closing;
  Completer<void>? _drained;

  /// Physical requests admitted, including running inference.
  int get pending => _queue.length + (_running ? 1 : 0);

  @override
  Future<Map<String, String>> answer(LayaDecisionQuery query) async => {
    for (final entry in (await answerDecisions(query)).entries)
      entry.key: entry.value.optionId,
  };

  @override
  Future<Map<String, LayaDecisionResult>> answerDecisions(
    LayaDecisionQuery query,
  ) {
    if (_closed) {
      return Future.error(const LayaServingException('laya_engine_closed'));
    }
    if (pending >= maxPending) {
      return Future.error(
        const LayaServingException('laya_queue_full', statusCode: 429),
      );
    }
    // Freeze caller-owned maps before an asynchronous handoff. Each job carries
    // only that request; neither model state nor diagnostics cache actor text.
    final snapshot = LayaDecisionQuery(
      model: query.model,
      state: query.state,
      questions: Map.unmodifiable({
        for (final entry in query.questions.entries)
          entry.key: LayaDecisionQuestion(
            id: entry.value.id,
            instructions: entry.value.instructions,
            criteria: Map.unmodifiable(entry.value.criteria),
          ),
      }),
    );
    final job = _Job(snapshot);
    _queue.add(job);
    if (!_running) unawaited(_pump());
    return job.result.future;
  }

  Future<void> _pump() async {
    _running = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      try {
        final result = await executor.compute(_answer, (
          engine: _engine,
          query: job.query,
        ));
        job.result.complete(result);
      } on Object catch (error, stack) {
        job.result.completeError(error, stack);
      }
    }
    _running = false;
    _drained?.complete();
    _drained = null;
  }

  /// Stop admission and wait for physical work; never kill a running native
  /// call or unload a model while another actor's inference uses it.
  Future<void> dispose() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    if (_running) {
      _drained ??= Completer<void>();
      await _drained!.future;
    }
    await _disposeEngine?.call();
  }
}

Future<NativeLayaDecisionEngine> _loadNative(String? modelDir) =>
    NativeLayaDecisionEngine.load(modelDir: modelDir);

FutureOr<Map<String, LayaDecisionResult>> _answer(
  ({CalibratedLayaDecisionEngine engine, LayaDecisionQuery query}) input,
) => input.engine.answerDecisions(input.query);

final class _Job {
  _Job(this.query);
  final LayaDecisionQuery query;
  final result = Completer<Map<String, LayaDecisionResult>>();
}
