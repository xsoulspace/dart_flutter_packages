/// Pure-Dart contracts for the universal automation family.
///
/// This package defines the vocabulary shared by automation drivers and
/// frame pipelines: endpoints and session handles (oka-compatible), the
/// observe/act/verify driver contract, semantic snapshot types, fail-closed
/// typed specs, and structured events. It deliberately contains no protocol
/// clients and no lifecycle ownership — see the sibling packages
/// `universal_browser_cdp`, `universal_browser_webdriver`, and
/// `universal_screencast`.
///
/// Naming and semantics follow the oka session contract:
/// `session-<name>-handle` is the primary handle artifact and
/// `session-<name>-<sub>` are sub-handles. `LeaseOwnership.borrowed` marks
/// endpoints this package family must never stop.
library;

export 'src/automation_action.dart';
export 'src/automation_endpoint.dart';
export 'src/automation_event.dart';
export 'src/automation_exceptions.dart';
export 'src/automation_session.dart';
export 'src/automation_spec.dart';
export 'src/driver.dart';
export 'src/driver_capabilities.dart';
export 'src/snapshot.dart';
