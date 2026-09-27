import 'package:meta/meta.dart';

/// What a driver can do, declared up front so compositions can validate
/// before attaching (the `StorageCapabilities` pattern).
@immutable
class DriverCapabilities {
  /// Creates a capability set.
  const DriverCapabilities({
    this.attach = true,
    this.screenshot = false,
    this.screencast = false,
    this.a11yTree = false,
    this.inputSynthesis = false,
    this.evaluate = false,
  });

  /// The canonical all-features set.
  static const DriverCapabilities full = DriverCapabilities(
    screenshot: true,
    screencast: true,
    a11yTree: true,
    inputSynthesis: true,
    evaluate: true,
  );

  /// Attaching to an existing target is supported.
  final bool attach;

  /// Single-frame screenshots (`AutomationDriver.screenshot`).
  final bool screenshot;

  /// Continuous frames (screencast package sources).
  final bool screencast;

  /// Semantic/accessibility snapshots (`AutomationDriver.snapshot`).
  final bool a11yTree;

  /// Input synthesis (`AutomationDriver.perform`).
  final bool inputSynthesis;

  /// Read-only evaluation (`EvaluateAction`).
  final bool evaluate;

  /// Serializes the capability set.
  Map<String, Object?> toJson() => {
    'attach': attach,
    'screenshot': screenshot,
    'screencast': screencast,
    'a11yTree': a11yTree,
    'inputSynthesis': inputSynthesis,
    'evaluate': evaluate,
  };

  @override
  String toString() => 'DriverCapabilities${toJson()}';
}
