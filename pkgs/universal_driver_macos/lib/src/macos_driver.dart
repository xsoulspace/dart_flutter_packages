import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'driver_bridge.dart';

/// The host refuses to answer AX queries until the user grants
/// Accessibility (System Settings → Privacy & Security). Fixable
/// environment state; retry after [MacosDriver.requestTrust] succeeds.
final class AccessibilityPermissionRequiredException
    extends AutomationException {
  /// Creates the exception.
  const AccessibilityPermissionRequiredException()
    : super(
        'Accessibility permission required for universal_driver_macos; '
        'grant it in System Settings (or call requestTrust once)',
      );

  @override
  String get kind => 'permissionRequired';
}

/// [AutomationDriver] over the macOS accessibility tree (AXUIElement) and
/// CGEvent input synthesis.
///
/// Observe: the focused application's tree, depth-bounded, mapped onto the
/// family's [Snapshot]; plus [elementAtPosition] hit-testing for hover
/// affordances (the Vosges use case). Act: AXPress for semantic clicks,
/// CGEvent for typing, keys, and scrolling. Verify: snapshot deltas.
///
/// Element handles cached by the native bridge are invalidated by every
/// new observation; a click on a stale handle transparently re-observes
/// once before giving up.
class MacosDriver implements AutomationDriver {
  /// Creates a driver. [snapshotDepth] and [snapshotMaxNodes] bound the
  /// tree walk (AX trees of real apps can be enormous; hover needs only
  /// the visible surface).
  MacosDriver({
    AxDriverBridge? bridge,
    this.snapshotDepth = 12,
    this.snapshotMaxNodes = 600,
  }) : bridge = bridge ?? NativeAxDriverBridge();

  /// The native bridge seam.
  final AxDriverBridge bridge;

  /// Maximum tree depth per snapshot.
  final int snapshotDepth;

  /// Maximum node count per snapshot.
  final int snapshotMaxNodes;

  bool _closed = false;
  int _revision = 0;
  Snapshot? _lastSnapshot;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
  );

  /// Whether the process may query the accessibility tree right now.
  bool get axTrusted {
    _ensureOpen();
    return bridge.axTrusted();
  }

  /// Raises the system consent prompt when untrusted; returns the
  /// resulting status (a manual System Settings step may still be needed).
  bool requestTrust() {
    _ensureOpen();
    return bridge.requestTrust();
  }

  /// The accessibility element at top-left-origin screen coordinates
  /// (the same system CGEvent mouse coordinates use). This is the hover
  /// query: throttle it to pointer-cadence, never per frame.
  Future<AxNode> elementAtPosition(double x, double y) async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    final result = bridge.elementAtPositionJson(x: x, y: y);
    final node = _nodeFromResult(result, 'elementAtPosition');
    return node;
  }

  @override
  Future<Snapshot> snapshot() async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    final result = bridge.snapshotJson(
      maxDepth: snapshotDepth,
      maxNodes: snapshotMaxNodes,
    );
    final root = _nodeFromResult(result, 'snapshot');
    _revision += 1;
    _lastSnapshot = Snapshot(
      roots: [root],
      capturedAt: DateTime.now().toUtc(),
      revision: _revision,
    );
    return _lastSnapshot!;
  }

  @override
  Future<void> perform(AutomationAction action) async {
    _ensureOpen();
    switch (action) {
      case ClickAction(:final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; click by role or name '
            '(resolved against the latest snapshot)',
          );
        }
        await _click(role: role, name: name);
      case TypeAction(:final text, :final css, :final submit):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; the focused control receives '
            'the text (focus one via ClickAction first)',
          );
        }
        _check(bridge.typeText(text), 'type text');
        if (submit) _check(bridge.keyPress('Enter'), 'press Enter');
      case KeyPressAction(:final key):
        final code = bridge.keyPress(key);
        if (code == 1) {
          throw DriverUnsupportedException(
            'key "$key" is not mapped by the macOS driver',
          );
        }
        _check(code, 'press key $key');
      case ScrollAction(:final direction, :final distance):
        await _scroll(direction, distance);
      case NavigateAction(:final url):
        throw DriverUnsupportedException(
          'AX has no navigation surface (target: $url); navigation is a '
          'browser-protocol capability',
        );
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'AX cannot evaluate expressions (${expression.length} chars); '
          'evaluation is an instrumented-tier capability',
        );
    }
  }

  @override
  Future<Uint8List> screenshot() async {
    _ensureOpen();
    final result = bridge.screenshotPng();
    if (result.code == 10) {
      throw const AccessibilityPermissionRequiredException();
    }
    if (result.code != 0) {
      throw ProtocolException('screenshot failed', code: result.code);
    }
    return result.bytes;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    bridge.releaseAll();
  }

  Future<void> _click({String? role, String? name}) async {
    var handle = _resolveHandle(role: role, name: name);
    if (handle == null) {
      // Locators go stale as surfaces change; re-observe once before
      // declaring the element missing.
      await snapshot();
      handle = _resolveHandle(role: role, name: name);
    }
    if (handle == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name ?? '',
      );
    }
    final code = bridge.press(handle);
    if (code == 5) {
      // Stale native handle (surface rebuilt between snapshot and press).
      await snapshot();
      final retry = _resolveHandle(role: role, name: name);
      if (retry == null) {
        throw ElementNotFoundException(
          role != null ? 'role' : 'name',
          role ?? name ?? '',
        );
      }
      _check(bridge.press(retry), 'press');
      return;
    }
    _check(code, 'press');
  }

  int? _resolveHandle({String? role, String? name}) {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return null;
    for (final node in snapshot.nodes) {
      final roleMatches = role == null || node.role == role.toLowerCase();
      final nameMatches = name == null || node.name == name;
      if (roleMatches && nameMatches) {
        final raw = node.attributes['axid'];
        final handle = raw == null ? null : int.tryParse(raw);
        if (handle != null) return handle;
      }
    }
    return null;
  }

  Future<void> _scroll(String direction, double? distance) async {
    final normalized = direction.toLowerCase();
    final lines = (distance ?? 30) / 10; // ~10 px per wheel line.
    final dx = switch (normalized) {
      'right' => lines,
      'left' => -lines,
      _ => 0.0,
    };
    final dy = switch (normalized) {
      'up' => lines,
      'down' => -lines,
      _ => 0.0,
    };
    if (dx == 0 && dy == 0) {
      throw DriverUnsupportedException(
        'scroll direction "$direction" is not one of up/down/left/right',
      );
    }
    _check(bridge.scroll(dx, dy), 'scroll $normalized');
  }

  AxNode _nodeFromResult(BridgeJsonResult result, String operation) {
    switch (result.code) {
      case 0:
        break;
      case 2:
        throw ElementNotFoundException('focusedApplication', operation);
      case 4:
        throw ElementNotFoundException('position', operation);
      case 10:
        throw const AccessibilityPermissionRequiredException();
      default:
        throw ProtocolException('$operation failed', code: result.code);
    }
    final decoded = jsonDecode(result.json);
    if (decoded is! Map<String, Object?>) {
      throw ProtocolException('$operation returned a non-object payload');
    }
    return AxNode.fromJson(decoded);
  }

  void _check(int code, String operation) {
    if (code == 0) return;
    if (code == 5) {
      throw ProtocolException(
        '$operation hit a stale element handle',
        code: code,
      );
    }
    throw ProtocolException('$operation failed', code: code);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('MacosDriver is closed');
  }
}
