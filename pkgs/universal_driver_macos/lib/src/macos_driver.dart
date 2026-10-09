import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'driver_bridge.dart';
import 'macos_app.dart';

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

/// [Screen Recording] consent is a separate TCC grant from
/// Accessibility: tree reads and input injection need the latter, any
/// pixel capture needs the former. The typed exceptions keep the two
/// fixable states apart.
final class ScreenRecordingPermissionRequiredException
    extends AutomationException {
  /// Creates the exception.
  const ScreenRecordingPermissionRequiredException()
    : super(
        'Screen Recording permission required for capture; grant it in '
        'System Settings → Privacy & Security → Screen & System Audio',
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
  DateTime? _lastObservationAt;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
    pointerCoordinates: true,
  );

  /// When the last snapshot was taken — the reference point for the
  /// behavior layer's reaction floor.
  DateTime? get lastObservationAt => _lastObservationAt;

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

  // -- APP MANAGEMENT (the macOS rung: manage APPLICATIONS, not only
  // whatever currently holds focus) --

  /// The running, Dock-able applications — the discovery record every
  /// app-targeted call consumes.
  Future<List<MacosApp>> runningApps() async {
    _ensureOpen();
    final result = bridge.appsJson();
    if (result.code != 0) {
      throw ProtocolException('runningApps failed', code: result.code);
    }
    return MacosApp.listFromJson(result.json);
  }

  /// The application that currently owns the key window.
  Future<MacosApp> frontmost() async {
    _ensureOpen();
    final result = bridge.frontmostJson();
    if (result.code == 2) {
      throw const ElementNotFoundException('frontmostApplication', 'frontmost');
    }
    if (result.code != 0) {
      throw ProtocolException('frontmost failed', code: result.code);
    }
    final decoded = jsonDecode(result.json);
    if (decoded is! Map<String, Object?>) {
      throw const ProtocolException('frontmost returned a non-object');
    }
    return MacosApp.fromJson(decoded);
  }

  /// Brings the application with [pid] to the front.
  Future<void> activate(int pid) async {
    _ensureOpen();
    final code = bridge.activateApp(pid);
    if (code == 7) {
      throw ElementNotFoundException('application', 'activate pid=$pid');
    }
    if (code != 0) {
      throw ProtocolException('activate failed', code: code);
    }
  }

  /// Launches (or activates, if already running) [bundleId]; returns the
  /// application's pid.
  Future<int> launch(String bundleId) async {
    _ensureOpen();
    final pid = bridge.launchApp(bundleId);
    if (pid == -7) {
      throw ElementNotFoundException('application', 'launch $bundleId');
    }
    if (pid < 0) {
      throw ProtocolException('launch failed', code: pid);
    }
    return pid;
  }

  /// Asks the application with [pid] to quit (graceful terminate).
  Future<void> terminate(int pid) async {
    _ensureOpen();
    final code = bridge.terminateApp(pid);
    if (code == 7) {
      throw ElementNotFoundException('application', 'terminate pid=$pid');
    }
    if (code != 0) {
      throw ProtocolException('terminate failed', code: code);
    }
  }

  /// The on-screen, normal-layer windows owned by [pid]
  /// (0 = every regular app) — the discovery record window-scoped
  /// capture consumes.
  Future<List<MacosWindow>> windows({int pid = 0}) async {
    _ensureOpen();
    final result = bridge.windowsJson(pid: pid);
    if (result.code != 0) {
      throw ProtocolException('windows failed', code: result.code);
    }
    return MacosWindow.listFromJson(result.json);
  }

  /// Captures one window's PNG (occlusion included, exact window
  /// bounds); [maxPx] caps the long side when set. Needs Screen
  /// Recording consent, not Accessibility.
  Future<Uint8List> windowScreenshot(int windowId, {int? maxPx}) async {
    _ensureOpen();
    final result = bridge.screenshotWindowPng(
      windowId: windowId,
      maxPx: maxPx ?? 0,
    );
    if (result.code == 10) {
      throw const ScreenRecordingPermissionRequiredException();
    }
    if (result.code == 2) {
      throw ElementNotFoundException('window', 'screenshot #$windowId');
    }
    if (result.code != 0) {
      throw ProtocolException('window screenshot failed', code: result.code);
    }
    return result.bytes;
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
    return _snapshotFrom(result);
  }

  /// Observes ANY running application's tree by pid — the background-app
    /// read the focused-app-only [snapshot] could not do (7 = unknown pid).
  Future<Snapshot> snapshotOfApp(int pid) async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    final result = bridge.snapshotAppJson(
      maxDepth: snapshotDepth,
      maxNodes: snapshotMaxNodes,
      pid: pid,
    );
    if (result.code == 7) {
      throw ElementNotFoundException('application', 'snapshot pid=$pid');
    }
    return _snapshotFrom(result);
  }

  Snapshot _snapshotFrom(BridgeJsonResult result) {
    final root = _nodeFromResult(result, 'snapshot');
    _revision += 1;
    _lastObservationAt = DateTime.now();
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
      case KeyPressAction(:final key, :final modifiers):
        if (modifiers.isEmpty) {
          final code = bridge.keyPress(key);
          if (code == 1) {
            throw DriverUnsupportedException(
              'key "$key" is not mapped by the macOS driver',
            );
          }
          _check(code, 'press key $key');
        } else {
          // The chord: hold the modifiers, tap the key, release in
          // reverse — each modifier key event announces its flag.
          for (final modifier in modifiers) {
            _check(
              bridge.keyDown(modifierKeyName(modifier)),
              'hold ${modifierKeyName(modifier)}',
            );
          }
          final code = bridge.keyPress(key);
          if (code == 1) {
            throw DriverUnsupportedException(
              'key "$key" is not mapped by the macOS driver',
            );
          }
          _check(code, 'press key $key');
          for (final modifier in modifiers.reversed) {
            _check(
              bridge.keyUp(modifierKeyName(modifier)),
              'release ${modifierKeyName(modifier)}',
            );
          }
        }
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
      case InvokeAction(:final name):
        throw DriverUnsupportedException(
          'the AX tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
        );
      case ClickAtAction(
        :final x,
        :final y,
        :final button,
        :final clickCount,
        :final modifiers,
      ):
        // Chord lowering (ADR 0053): the bridge posts the modifier key
        // events (each announces its CGEventFlag) and the pointer
        // events carry the same mask, so the host sees one chord.
        for (final modifier in modifiers) {
          _check(
            bridge.keyDown(modifierKeyName(modifier)),
            'hold ${modifierKeyName(modifier)}',
          );
        }
        _pointerCheck(
          bridge.pointerMove(x: x, y: y, modifiers: modifiers),
          'move pointer',
        );
        for (var press = 1; press <= clickCount.clamp(1, 3); press++) {
          _pointerCheck(
            bridge.pointerButton(
              x: x,
              y: y,
              button: button,
              down: true,
              clickCount: press,
              modifiers: modifiers,
            ),
            'press $button (click $press)',
          );
          _pointerCheck(
            bridge.pointerButton(
              x: x,
              y: y,
              button: button,
              down: false,
              clickCount: press,
              modifiers: modifiers,
            ),
            'release $button (click $press)',
          );
        }
        for (final modifier in modifiers.reversed) {
          _check(
            bridge.keyUp(modifierKeyName(modifier)),
            'release ${modifierKeyName(modifier)}',
          );
        }
      case MoveAction(:final x, :final y):
        _pointerCheck(bridge.pointerMove(x: x, y: y), 'move pointer');
      case DragAction(
        :final fromX,
        :final fromY,
        :final toX,
        :final toY,
        :final button,
        :final modifiers,
      ):
        for (final modifier in modifiers) {
          _check(
            bridge.keyDown(modifierKeyName(modifier)),
            'hold ${modifierKeyName(modifier)}',
          );
        }
        _pointerCheck(
          bridge.pointerMove(x: fromX, y: fromY, modifiers: modifiers),
          'drag approach',
        );
        _pointerCheck(
          bridge.pointerButton(
            x: fromX,
            y: fromY,
            button: button,
            down: true,
            modifiers: modifiers,
          ),
          'press $button',
        );
        // The bridge posts carried moves as dragged events while the
        // button is down, so this reads as one gesture on the host.
        _pointerCheck(
          bridge.pointerMove(x: toX, y: toY, modifiers: modifiers),
          'drag carry',
        );
        _pointerCheck(
          bridge.pointerButton(
            x: toX,
            y: toY,
            button: button,
            down: false,
            modifiers: modifiers,
          ),
          'release $button',
        );
        for (final modifier in modifiers.reversed) {
          _check(
            bridge.keyUp(modifierKeyName(modifier)),
            'release ${modifierKeyName(modifier)}',
          );
        }
    }
  }

  /// Captures the main display; [maxPx] caps the long side when set
  /// (the agent-facing image budget). Needs Screen Recording consent.
  @override
  Future<Uint8List> screenshot({int? maxPx}) async {
    _ensureOpen();
    final result = bridge.screenshotPng(maxPx: maxPx ?? 0);
    if (result.code == 10) {
      throw const ScreenRecordingPermissionRequiredException();
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

  /// Pointer-verb bridge codes map to the same table, with the
  /// Accessibility grant surfacing as the typed permission exception.
  void _pointerCheck(int code, String operation) {
    if (code == 0) return;
    if (code == 10) {
      throw const AccessibilityPermissionRequiredException();
    }
    if (code == 1) {
      throw DriverUnsupportedException(
        '$operation: the macOS bridge does not map that button name '
        '(use left, right, or middle)',
      );
    }
    throw ProtocolException('$operation failed', code: code);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('MacosDriver is closed');
  }
}
