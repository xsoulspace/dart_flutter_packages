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
    this.behaviorDynamics = false,
    this.pointerCoordinates = false,
    this.semanticWrite = false,
    this.pidScopedEvents = false,
  });

  /// The canonical all-features set.
  static const DriverCapabilities full = DriverCapabilities(
    screenshot: true,
    screencast: true,
    a11yTree: true,
    inputSynthesis: true,
    evaluate: true,
    behaviorDynamics: true,
    pointerCoordinates: true,
    semanticWrite: true,
    pidScopedEvents: true,
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

  /// Declarative behavior delivery (`BehavioralDriver.performWith`).
  final bool behaviorDynamics;

  /// Coordinate pointer verbs (`ClickAtAction`, `MoveAction`,
  /// `DragAction` — ADR 0053). False means those actions refuse loudly;
  /// locator verbs are unaffected.
  final bool pointerCoordinates;

  /// Semantic element writes (`SetValueAction`, `ElementAction` —
  /// ADR 0064): act below the focus layer, valid on background targets.
  /// False means those actions refuse loudly.
  final bool semanticWrite;

  /// Keyboard events (`TypeAction`, `KeyPressAction`) can be delivered
  /// to an anchored background target without moving focus (ADR 0064
  /// rung — macOS `CGEventPostToPid`). Pointer/scroll verbs are not
  /// covered: they carry global screen coordinates.
  final bool pidScopedEvents;

  /// Serializes the capability set.
  Map<String, Object?> toJson() => {
    'attach': attach,
    'screenshot': screenshot,
    'screencast': screencast,
    'a11yTree': a11yTree,
    'inputSynthesis': inputSynthesis,
    'evaluate': evaluate,
    'behaviorDynamics': behaviorDynamics,
    'pointerCoordinates': pointerCoordinates,
    'semanticWrite': semanticWrite,
    'pidScopedEvents': pidScopedEvents,
  };

  @override
  String toString() => 'DriverCapabilities${toJson()}';
}
