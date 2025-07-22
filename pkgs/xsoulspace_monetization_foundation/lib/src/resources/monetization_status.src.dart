import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import '../models/models.dart';

/// {@template monetization_status_resource}
/// Resource that manages the overall status of the monetization system.
///
/// This resource tracks the initialization and availability state of the
/// monetization system across all platforms and providers.
///
/// ## States:
/// - `loading`: System is initializing
/// - `loaded`: System is ready and available
/// - `notAvailable`: System failed to initialize
/// - `storeNotAuthorized`: Store requires user authorization
///
/// ## Usage
/// ```dart
/// final statusResource = MonetizationStatusResource();
///
/// // Listen for changes
/// statusResource.addListener(() {
///   if (statusResource.isInitialized) {
///     // System is ready
///   }
/// });
///
/// // Update status
/// statusResource.setStatus(MonetizationStatus.loaded);
/// ```
/// {@endtemplate}
@stateDistributor
class MonetizationStatusResource extends ChangeNotifier {
  /// {@macro monetization_status_resource}
  MonetizationStatusResource();

  MonetizationStatus _status = MonetizationStatus.loading;

  /// Returns `true` if the monetization system is fully initialized and ready.
  bool get isInitialized => _status == MonetizationStatus.loaded;

  /// Current status of the monetization system.
  MonetizationStatus get status => _status;

  /// Updates the monetization system status and notifies listeners.
  void setStatus(final MonetizationStatus value) {
    _status = value;
    notifyListeners();
  }
}
