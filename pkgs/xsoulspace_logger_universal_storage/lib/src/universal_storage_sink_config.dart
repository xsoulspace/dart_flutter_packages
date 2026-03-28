
/// Runtime settings for [UniversalStorageSink].
final class UniversalStorageSinkConfig {
  const UniversalStorageSinkConfig({
    this.appendFileName = 'append.ndjson',
    this.snapshotFileName = 'snapshot.json',
    this.compactionEvery = 2048,
    this.snapshotMaxRecords = 10000,
    this.schemaVersion = 1,
    this.persistedStackTraceLines = 120,
  }) : assert(compactionEvery > 0),
       assert(snapshotMaxRecords > 0),
       assert(schemaVersion > 0),
       assert(persistedStackTraceLines > 0);

  final String appendFileName;
  final String snapshotFileName;
  final int compactionEvery;
  final int snapshotMaxRecords;
  final int schemaVersion;
  final int persistedStackTraceLines;
}
