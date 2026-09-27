import 'package:meta/meta.dart';

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
/// `ArrowUp`/`Down`/`Left`/`Right`).
@immutable
final class KeyPressAction extends AutomationAction {
  /// Creates a key press action.
  const KeyPressAction(this.key);

  /// Logical key name; see the class docs for the supported set.
  final String key;

  @override
  String toString() => 'KeyPressAction($key)';
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
