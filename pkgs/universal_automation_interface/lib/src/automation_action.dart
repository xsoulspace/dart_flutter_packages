import 'package:meta/meta.dart';

/// Renders the chord suffix for action toString output.
String _chordSuffix(final List<String> modifiers) =>
    modifiers.isEmpty ? '' : ' +${modifiers.join('+')}';

/// Base class of driver actions.
///
/// Actions are intent-level values; each driver maps them onto its protocol.
/// Drivers must refuse unsupported actions with
/// `DriverUnsupportedException` rather than silently degrading.
sealed class AutomationAction {
  /// Creates an action.
  const AutomationAction();
}

/// Navigate the surface to [url].
@immutable
final class NavigateAction extends AutomationAction {
  /// Creates a navigation action.
  const NavigateAction(this.url);

  /// Destination URI.
  final Uri url;

  @override
  String toString() => 'NavigateAction($url)';
}

/// Click an element located by CSS selector, or by role/name when the
/// driver resolves roles through its semantic tree.
@immutable
final class ClickAction extends AutomationAction {
  /// Creates a click action. At least one locator must be set.
  const ClickAction({this.css, this.role, this.name})
    : assert(
        css != null || role != null || name != null,
        'ClickAction needs a css selector, role, or name',
      );

  /// CSS selector locator, when used.
  final String? css;

  /// Semantic role locator, when used.
  final String? role;

  /// Accessible-name locator, when used.
  final String? name;

  @override
  String toString() => 'ClickAction(css: $css, role: $role, name: $name)';
}

/// Focus an element and type [text] into it.
@immutable
final class TypeAction extends AutomationAction {
  /// Creates a typing action. [submit] presses Enter afterwards.
  const TypeAction(this.text, {this.css, this.submit = false});

  /// Text to type.
  final String text;

  /// CSS selector of the element to focus first, when used.
  final String? css;

  /// Whether to press Enter after typing.
  final bool submit;

  @override
  String toString() => 'TypeAction(${text.length} chars, css: $css)';
}

/// Press a named key (`Enter`, `Tab`, `Escape`, `Backspace`,
/// `ArrowUp`/`Down`/`Left`/`Right`, and the modifier names
/// `Shift`/`Control`/`Alt`/`Meta`), optionally under [modifiers] — a
/// chord like `control`+`T` (ADR 0053).
@immutable
final class KeyPressAction extends AutomationAction {
  /// Creates a key press action.
  const KeyPressAction(this.key, {this.modifiers = const []});

  /// Logical key name; see the class docs for the supported set.
  final String key;

  /// Keyboard modifiers held while the key presses: a subset of
  /// `shift`/`control`/`alt`/`meta`, normalized lowercase.
  final List<String> modifiers;

  @override
  String toString() => 'KeyPressAction($key${_chordSuffix(modifiers)})';
}

/// Scroll the surface (or the scrollable containing [css]) by
/// [distance] logical pixels in [direction].
///
/// [direction] is one of `up`, `down`, `left`, `right` (lowercase;
/// drivers normalize case). `distance` may be null — the driver then
/// uses its default step. Scrolling is how off-screen semantics become
/// visible: the instrumented tier exposes them only once scrolled into
/// view.
@immutable
final class ScrollAction extends AutomationAction {
  /// Creates a scroll action.
  const ScrollAction({this.direction = 'down', this.distance});

  /// Scroll direction: `up`, `down`, `left`, or `right`.
  final String direction;

  /// Distance in logical pixels; null means the driver's default step.
  final double? distance;

  @override
  String toString() =>
      'ScrollAction($direction, ${distance ?? 'default'})';
}

/// Evaluate a read-only expression in the live surface.
///
/// Drivers may refuse evaluation (capability `evaluate` is `false`); when
/// supported the result is best-effort JSON-encodable.
@immutable
final class EvaluateAction extends AutomationAction {
  /// Creates an evaluate action.
  const EvaluateAction(this.expression);

  /// Expression source text.
  final String expression;

  @override
  String toString() => 'EvaluateAction(${expression.length} chars)';
}

/// Click at surface coordinates — the fallback tier for surfaces no
/// accessibility tree can see (canvas, games) and for pixel-grounded
/// agents (ADR 0053). Capability `pointerCoordinates`; drivers without
/// it refuse loudly.
@immutable
final class ClickAtAction extends AutomationAction {
  /// Creates a click at ([x], [y]) in surface coordinates.
  const ClickAtAction(
    this.x,
    this.y, {
    this.button = 'left',
    this.clickCount = 1,
    this.modifiers = const [],
  });

  /// X in surface (CSS px on the web tier, screen points on OS tiers).
  final double x;

  /// Y in surface coordinates.
  final double y;

  /// Pointer button: `left` (default), `right`, or `middle`.
  final String button;

  /// 1 = click, 2 = double-click, 3 = triple.
  final int clickCount;

  /// Keyboard modifiers held through the click (`shift`+click,
  /// `meta`+click) — a subset of `shift`/`control`/`alt`/`meta`,
  /// normalized lowercase (ADR 0053).
  final List<String> modifiers;

  @override
  String toString() =>
      'ClickAtAction($x, $y, $button, x$clickCount'
      '${_chordSuffix(modifiers)})';
}

/// Move the pointer to ([x], [y]) without pressing — hover affordances,
/// tooltips, pre-positioning before a drag (ADR 0053).
@immutable
final class MoveAction extends AutomationAction {
  /// Creates a pointer move to ([x], [y]).
  const MoveAction(this.x, this.y);

  /// X in surface coordinates.
  final double x;

  /// Y in surface coordinates.
  final double y;

  @override
  String toString() => 'MoveAction($x, $y)';
}

/// Press at [fromX]/[fromY], move to [toX]/[toY], release — drag and
/// drop, sliders, canvas gestures (ADR 0053). Behavioral profiles
/// lower the whole path through humanized segments; plain dispatch is
/// one press, one move, one release.
@immutable
final class DragAction extends AutomationAction {
  /// Creates a drag from (fromX, fromY) to (toX, toY).
  const DragAction(
    this.fromX,
    this.fromY,
    this.toX,
    this.toY, {
    this.button = 'left',
    this.modifiers = const [],
  });

  /// Press X in surface coordinates.
  final double fromX;

  /// Press Y in surface coordinates.
  final double fromY;

  /// Release X in surface coordinates.
  final double toX;

  /// Release Y in surface coordinates.
  final double toY;

  /// Pointer button held through the drag: `left` (default), `right`,
  /// or `middle`.
  final String button;

  /// Keyboard modifiers held through the drag (`meta`+drag for window
  /// moves, `shift`+drag for constrained axes) — a subset of
  /// `shift`/`control`/`alt`/`meta`, normalized lowercase (ADR 0053).
  final List<String> modifiers;

  @override
  String toString() =>
      'DragAction(($fromX, $fromY) → ($toX, $toY), $button'
      '${_chordSuffix(modifiers)})';
}

/// Invoke a named action the surface under test registered for automation
/// (the `invoke` tier — the dynamic-registry shape for drivers).
///
/// The universal verbs above stay deliberately small: growing them is a
/// family-wide release. Everything framework- or app-specific — a gesture
/// choreography, a checkout flow, a Jaspr component contract, a test
/// backdoor — travels through [InvokeAction] instead, against the action
/// catalog the surface advertises (see [AutomationActionCatalog]).
///
/// Names and argument schemas come from that catalog; drivers refuse
/// unknown names with `DriverUnsupportedException`, and surfaced actions
/// validate on their own tier (the instrumented tier checks before the
/// wire, the CDP tier inside the page).
@immutable
final class InvokeAction extends AutomationAction {
  /// Creates an invoke action for [name].
  const InvokeAction(this.name, {this.args = const {}})
    : assert(name != '', 'name must not be empty');

  /// The catalog name of the surface action.
  final String name;

  /// JSON-encodable arguments, shaped by the action's declared schema.
  final Map<String, Object?> args;

  @override
  String toString() => 'InvokeAction($name)';
}
