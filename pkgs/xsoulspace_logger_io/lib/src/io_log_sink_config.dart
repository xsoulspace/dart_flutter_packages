
/// Runtime configuration for [IoLogSink].
final class IoLogSinkConfig {
  const IoLogSinkConfig({
    required this.directoryPath,
    this.segmentMaxBytes = 8 * 1024 * 1024,
    this.retentionMaxAge = const Duration(days: 7),
    this.retentionMaxBytes = 50 * 1024 * 1024,
    this.fsyncInterval = const Duration(seconds: 5),
    this.schemaVersion = 1,
    this.segmentPrefix = 'segment_',
    this.segmentExtension = '.ndjson',
    this.persistedStackTraceLines = 120,
  }) : assert(segmentMaxBytes > 0),
       assert(retentionMaxBytes > 0),
       assert(fsyncInterval > Duration.zero),
       assert(schemaVersion > 0),
       assert(persistedStackTraceLines > 0);

  final String directoryPath;
  final int segmentMaxBytes;
  final Duration retentionMaxAge;
  final int retentionMaxBytes;
  final Duration fsyncInterval;
  final int schemaVersion;
  final String segmentPrefix;
  final String segmentExtension;
  final int persistedStackTraceLines;
}
