/// Declarative frame pipeline for automation targets.
///
/// Frames are **read-only observations**: they never mutate session state
/// and never replace semantic snapshots (`frames != semantics`). The
/// pipeline validates a composition *before anything runs* (oka pipeline
/// discipline), then pumps frames from one [FrameSource] to many
/// [FrameSink]s with per-sink isolation:
///
/// - a failing sink degrades alone (`SinkDegraded`), others continue;
/// - a failing source fails the pipeline (`PipelineFailed`) and closes
///   every sink with the error — error-frame-then-close, never silence;
/// - slow sinks drop oldest frames instead of backpressuring the source;
/// - pacing and single-flight live at the source.
///
/// Consumers declare *who the frames are for* through
/// [ScreencastAudience]: agents get capped-fps keyframes correlated to
/// target revisions, humans get smooth MJPEG/WebSocket paths, recorders
/// get file receipts.
library;

export 'src/exceptions.dart';
export 'src/frame.dart';
export 'src/frame_sink.dart';
export 'src/frame_source.dart';
export 'src/screencast_audience.dart';
export 'src/screencast_pipeline.dart';
export 'src/sinks/file_recorder_sink.dart';
export 'src/sinks/mjpeg_http_sink.dart';
export 'src/sinks/websocket_frame_server.dart';
export 'src/sources/cdp_screencast_frame_source.dart';
export 'src/sources/polling_frame_source.dart';
