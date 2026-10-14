import 'dart:async';

import 'surface_action.dart';

/// Opt-in catalog of named actions a driver can invoke via
/// `InvokeAction`.
///
/// Drivers whose surface advertises an action registry implement this
/// alongside [AutomationDriver]: the instrumented tier lists what the app
/// registered, the CDP tier probes the page's `window.__mcpActions`
/// registry (so Jaspr, plain JS, and Flutter-web surfaces compose the same
/// way). Callers discover the surface's extra verbs at runtime instead of
/// waiting for a family release to grow the sealed verb set.
///
/// This is intentionally a separate interface, not an [AutomationDriver]
/// member: adding it is non-breaking, and drivers without a registry
/// (WebDriver, OS accessibility tiers) stay honest by absence.
// ignore: one_member_abstracts
abstract interface class AutomationActionCatalog {
  /// Lists the actions the connected surface registered, in catalog order.
  ///
  /// Returns an empty list when the surface advertises no registry —
  /// callers should treat that as "universal verbs only", not an error.
  Future<List<SurfaceActionDescriptor>> actions();
}
