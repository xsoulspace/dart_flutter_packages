/// macOS accessibility driver for the universal automation family.
///
/// Implements `AutomationDriver` over AXUIElement (semantic snapshot of
/// the focused application, element hit-testing for hover) and CGEvent
/// (typing, keys, scrolling, screenshots). Pure Dart through native-assets
/// build hooks; requires the Accessibility TCC grant for tree queries and
/// Screen Recording for `screenshot`.
///
/// ```dart
/// final driver = MacosDriver();
/// if (!driver.axTrusted) driver.requestTrust();
/// final snapshot = await driver.snapshot();
/// final target = snapshot.nodes.firstWhere((n) => n.role == 'button');
/// await driver.perform(ClickAction(name: target.name));
/// ```
///
/// The hover query the gesture product needs:
///
/// ```dart
/// final node = await driver.elementAtPosition(x, y); // top-left origin
/// ```
library;

export 'package:universal_automation_interface/universal_automation_interface.dart'
    show AutomationAction, AxNode, Snapshot;

export 'src/driver_bridge.dart';
export 'src/macos_app.dart';
export 'src/macos_behavior.dart';
export 'src/macos_driver.dart';
