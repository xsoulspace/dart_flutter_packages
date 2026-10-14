/// Conformance suites for the universal automation family.
///
/// Every `AutomationDriver`, `FrameSource`, and `FrameSink`
/// implementation must pass its suite to guarantee swappability — adopt
/// with one call from your own tests, exactly like
/// `universal_storage_conformance`:
///
/// ```dart
/// void main() {
///   automationDriverConformanceTests(
///     'CdpDriver over fake server',
///     createDriver: () async { /* build and return the driver */ },
///   );
/// }
/// ```
library;

export 'src/automation_driver_conformance.dart';
export 'src/behavior_synthesis_conformance.dart';
export 'src/frame_sink_conformance.dart';
export 'src/frame_source_conformance.dart';
