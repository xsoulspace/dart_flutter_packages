/// Who frames are for — the "for whom" axis of the pipeline.
///
/// Audience policies cap what a composition may promise: agents do not
/// need broadcast smoothness, humans do not tolerate 1 fps stalls,
/// recorders need durable receipts. Sinks not permitted by the declared
/// audiences are a composition error, not a runtime surprise.
enum ScreencastAudience {
  /// Vision-model sampling: capped fps, revision correlation matters more
  /// than smoothness.
  agent,

  /// Human operators: smoothness matters (WebSocket/MJPEG/WebRTC paths).
  human,

  /// Evidence and receipts: durability over latency.
  recorder,
}

/// Per-audience pacing floor. Agents are capped at ~5 fps: more frames
/// waste tokens and capture budget without adding decision value.
const _minIntervals = <ScreencastAudience, Duration>{
  ScreencastAudience.agent: Duration(milliseconds: 200),
  ScreencastAudience.human: Duration(milliseconds: 33),
  ScreencastAudience.recorder: Duration(milliseconds: 33),
};

/// The most restrictive pacing floor across [audiences].
Duration minFrameIntervalFor(Iterable<ScreencastAudience> audiences) {
  var result = const Duration(milliseconds: 33);
  for (final audience in audiences) {
    final floor = _minIntervals[audience]!;
    if (floor > result) result = floor;
  }
  return result;
}
