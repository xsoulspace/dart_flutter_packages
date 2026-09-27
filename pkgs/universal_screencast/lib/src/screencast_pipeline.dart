import 'dart:async';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'frame.dart';
import 'frame_sink.dart';
import 'frame_source.dart';
import 'screencast_audience.dart';

/// Fail-closed composition: one source, many sinks, an audience set, and a
/// pacing floor.
///
/// Validation runs at construction — before anything starts (oka pipeline
/// discipline). Violations throw [SpecViolationException] listing every
/// problem at once.
class ScreencastComposition {
  /// Creates and validates the composition.
  ScreencastComposition({
    required this._source,
    required List<FrameSink> sinks,
    List<ScreencastAudience> audiences = const [ScreencastAudience.agent],
    this._minFrameInterval,
  }) : _sinks = List.of(sinks),
       _audiences = List.of(audiences) {
    ensureValid();
  }

  final FrameSource _source;
  final List<FrameSink> _sinks;
  final List<ScreencastAudience> _audiences;
  final Duration? _minFrameInterval;

  /// The composed source.
  FrameSource get source => _source;

  /// The composed sinks (unmodifiable view).
  List<FrameSink> get sinks => List.unmodifiable(_sinks);

  /// Declared audiences.
  List<ScreencastAudience> get audiences => List.unmodifiable(_audiences);

  /// Effective pacing floor: the most restrictive audience floor, or the
  /// explicit override.
  Duration get minFrameInterval =>
      _minFrameInterval ?? minFrameIntervalFor(_audiences);

  /// Collects every violation; empty means valid.
  List<String> validate() {
    final violations = <String>[];
    if (_sinks.isEmpty) {
      violations.add('composition needs at least one sink');
    }
    if (_audiences.isEmpty) {
      violations.add('composition needs at least one audience');
    }
    for (final sink in _sinks) {
      final acceptable =
          sink.acceptedContentTypes.contains('*') ||
          sink.acceptedContentTypes.any(_source.capabilities.produces);
      if (!acceptable) {
        violations.add(
          'sink "${sink.id}" accepts ${sink.acceptedContentTypes.join('/')} '
          'but source "${_source.id}" produces '
          '${_source.capabilities.contentTypes.join('/')}',
        );
      }
    }
    final floor = minFrameInterval;
    final sourceCap = _source.capabilities.maxFps;
    if (sourceCap != null &&
        floor < Duration(milliseconds: 1000 ~/ sourceCap)) {
      violations.add(
        'pacing floor ${floor.inMilliseconds}ms is faster than source '
        '"${_source.id}" promises ($sourceCap fps)',
      );
    }
    return violations;
  }

  /// Throws [SpecViolationException] when violations exist.
  void ensureValid() {
    final violations = validate();
    if (violations.isNotEmpty) throw SpecViolationException(violations);
  }
}

/// A running pipeline: one source fanned out to many isolated sinks.
///
/// Start with [start]; observe [events]; stop with [stop]. The pipeline is
/// the only place where frames, events, and failure semantics meet.
class ScreencastPipeline {
  ScreencastPipeline._(this._composition) {
    for (final sink in _composition.sinks) {
      _pumps.add(_SinkPump(sink, _onSinkFailure));
    }
  }

  /// Starts the source and begins pumping frames.
  static Future<ScreencastPipeline> start(
    ScreencastComposition composition,
  ) async {
    final pipeline = ScreencastPipeline._(composition);
    final frames = composition.source.start();
    pipeline._events.add(SourceStarted(composition.source.id));
    pipeline._sourceSubscription = frames.listen(
      pipeline._onFrame,
      onError: (Object error) => pipeline._fail('sourceError', '$error'),
      onDone: () => pipeline._fail('sourceError', 'source ended unexpectedly'),
    );
    return pipeline;
  }

  final ScreencastComposition _composition;
  final _events = StreamController<AutomationEvent>.broadcast(sync: true);
  final _pumps = <_SinkPump>[];
  StreamSubscription<Frame>? _sourceSubscription;
  bool _stopped = false;

  /// Structured, payload-free pipeline events.
  Stream<AutomationEvent> get events => _events.stream;

  /// Stops the pipeline cleanly: source first, then sinks without error.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sourceSubscription?.cancel();
    await _composition.source.stop();
    _events.add(SourceStopped(_composition.source.id));
    for (final pump in _pumps) {
      await pump.close();
    }
    _pumps.clear();
    await _events.close();
  }

  void _onFrame(Frame frame) {
    if (_stopped) return;
    for (final pump in List.of(_pumps)) {
      pump.offer(frame);
    }
    _events.add(
      FrameDelivered(
        sourceId: frame.sourceId,
        sequence: frame.sequence,
        revision: frame.revision,
        byteLength: frame.bytes.length,
        contentType: frame.contentType,
        capturedAt: frame.capturedAt,
      ),
    );
  }

  Future<void> _onSinkFailure(_SinkPump pump, Object error) async {
    if (_stopped) return;
    _pumps.remove(pump);
    await pump.close(error: error);
    _events.add(SinkDegraded(pump.sink.id, '$error'));
    if (_pumps.isEmpty) {
      await _fail('allSinksLost', 'every sink left the pipeline');
    }
  }

  Future<void> _fail(String cause, String detail) async {
    if (_stopped) return;
    _stopped = true;
    await _sourceSubscription?.cancel();
    for (final pump in _pumps) {
      await pump.close(error: detail);
    }
    _pumps.clear();
    _events.add(PipelineFailed(cause, detail: detail));
    await _events.close();
  }
}

/// Per-sink serialized delivery with drop-oldest buffering: a slow sink
/// degrades its own freshness, never the source or other sinks.
class _SinkPump {
  _SinkPump(this.sink, this.onFailure);

  final FrameSink sink;
  final Future<void> Function(_SinkPump, Object) onFailure;
  final _queue = <Frame>[];
  bool _delivering = false;
  bool _closed = false;

  void offer(Frame frame) {
    if (_closed) return;
    if (_queue.length >= 2) {
      _queue.removeAt(0);
    }
    _queue.add(frame);
    if (!_delivering) unawaited(_drain());
  }

  Future<void> _drain() async {
    _delivering = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final frame = _queue.removeAt(0);
        await sink.push(frame);
      }
    } on Object catch (error) {
      if (!_closed) await onFailure(this, error);
    } finally {
      _delivering = false;
    }
  }

  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    _queue.clear();
    try {
      await sink.close(error: error);
    } on Object {
      // The sink is leaving either way; never mask the pipeline result.
    }
  }
}
