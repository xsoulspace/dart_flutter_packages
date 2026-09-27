import 'dart:typed_data';

import 'automation_action.dart';
import 'automation_exceptions.dart';
import 'driver_capabilities.dart';
import 'snapshot.dart';

/// The observe/act/verify contract every automation driver implements.
///
/// A driver attaches to an endpoint (CDP page, WebDriver session, VM
/// service, OS accessibility tree) and exposes one uniform loop. Drivers
/// declare [capabilities] up front; callers must check them and drivers
/// must throw [DriverUnsupportedException] when an excluded operation is
/// requested anyway.
abstract interface class AutomationDriver {
  /// Declared feature set.
  DriverCapabilities get capabilities;

  /// Observes the surface (`observe`).
  Future<Snapshot> snapshot();

  /// Performs an intent-level action (`act`).
  Future<void> perform(AutomationAction action);

  /// Captures one PNG frame, when `capabilities.screenshot` is set.
  Future<Uint8List> screenshot();

  /// Releases the driver. Idempotent; after close, every method throws.
  Future<void> close();
}
