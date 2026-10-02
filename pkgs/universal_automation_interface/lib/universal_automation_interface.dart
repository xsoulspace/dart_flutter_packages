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
export 'src/automation_action_catalog.dart';
export 'src/automation_endpoint.dart';
export 'src/automation_event.dart';
export 'src/automation_exceptions.dart';
export 'src/automation_session.dart';
export 'src/automation_spec.dart';
export 'src/behavior/behavior_audit.dart';
export 'src/behavior/behavior_hash.dart';
export 'src/behavior/behavior_profile.dart';
export 'src/behavior/behavior_receipt.dart';
export 'src/behavior/behavior_rng.dart';
export 'src/behavior/behavior_step.dart';
export 'src/behavior/behavior_synthesizer.dart';
export 'src/behavior/behavioral_driver.dart';
export 'src/behavior/canonical.dart';
export 'src/behavior/timing.dart';
export 'src/driver.dart';
export 'src/driver_capabilities.dart';
export 'src/snapshot.dart';
export 'src/surface_action.dart';
