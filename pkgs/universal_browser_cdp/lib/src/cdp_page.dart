import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';
import 'cdp_discovery.dart';

/// A page-level CDP facade: navigation, evaluation, accessibility
/// snapshots, screenshots, and trusted-input synthesis.
///
/// Input synthesis dispatches real `Input.dispatch*` events at resolved
/// element coordinates (not `element.click()` script calls), so the browser
/// treats them like user input.
class CdpPage {
  CdpPage._(this.connection, this.target);

  final CdpConnection connection;

  /// The page target this facade drives.
  final CdpTargetInfo target;
  int _revision = 0;
  bool _closed = false;

  /// Attaches the facade: enables `Page`, `Runtime`, and `Accessibility`
  /// domains.
  ///
  /// `Accessibility.enable` matters on real Chromium: without it the
  /// renderer keeps its AX tree uncomputed and `getFullAXTree` answers
  /// with the root node only (headless behaves this way reliably).
  static Future<CdpPage> attach(
    CdpConnection connection,
    CdpTargetInfo target,
  ) async {
    await connection.send('Page.enable');
    await connection.send('Runtime.enable');
    await connection.send('Accessibility.enable');
    return CdpPage._(connection, target);
  }

  /// Monotonic revision; bumps on every navigation.
  int get revision => _revision;

  /// Navigates the page and waits for the frame-navigated event.
  Future<void> navigate(Uri url) async {
    _ensureOpen();
    final navigated = connection
        .on('Page.frameNavigated')
        .first
        .timeout(const Duration(seconds: 15));
    await connection.send('Page.navigate', {'url': url.toString()});
    await navigated;
    _revision++;
  }

  /// Evaluates [expression] with `returnByValue` and returns the value.
  Future<Object?> evaluate(String expression) async {
    _ensureOpen();
    final result = await connection.send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': false,
    });
    return ((result['result'] as Map<String, Object?>?) ?? const {})['value'];
  }

  /// Captures the accessibility tree as an [Snapshot].
  ///
  /// Ignored nodes (`ignored: true`) are filtered out; the remaining nodes
  /// are rebuilt into a hierarchy via CDP `childIds`.
  Future<Snapshot> accessibilitySnapshot() async {
    _ensureOpen();
    final result = await connection.send('Accessibility.getFullAXTree');
    final raw = (result['nodes'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    return Snapshot(
      roots: _buildTree(raw),
      capturedAt: DateTime.now().toUtc(),
      revision: _revision,
    );
  }

  /// Captures one PNG screenshot.
  Future<Uint8List> screenshot({bool beyondViewport = false}) async {
    _ensureOpen();
    final result = await connection.send('Page.captureScreenshot', {
      'format': 'png',
      'captureBeyondViewport': beyondViewport,
    });
    final data = result['data'];
    if (data is! String) {
      throw const ProtocolException('Page.captureScreenshot returned no data');
    }
    return base64Decode(data);
  }

  /// Clicks the element at [css] by dispatching mouse events at its center.
  Future<void> click({required String css}) async {
    _ensureOpen();
    final rect = await _resolveRect(css);
    final (x, y) = rect.center;
    await connection.send('Input.dispatchMouseEvent', {
      'type': 'mousePressed',
      'x': x,
      'y': y,
      'button': 'left',
      'clickCount': 1,
    });
    await connection.send('Input.dispatchMouseEvent', {
      'type': 'mouseReleased',
      'x': x,
      'y': y,
      'button': 'left',
      'clickCount': 1,
    });
  }

  /// Focuses [css] (when given) and inserts [text]; [submit] presses Enter.
  Future<void> type(String text, {String? css, bool submit = false}) async {
    _ensureOpen();
    if (css != null) {
      await evaluate('document.querySelector(${_jsString(css)})?.focus()');
    }
    await connection.send('Input.insertText', {'text': text});
    if (submit) await keyPress('Enter');
  }

  /// Presses a named key. Supported: `Enter`, `Tab`, `Escape`,
  /// `Backspace`, `ArrowUp`/`Down`/`Left`/`Right`.
  Future<void> keyPress(String key) async {
    _ensureOpen();
    final code = _keyCodes[key];
    if (code == null) {
      throw DriverUnsupportedException(
        'key "$key" is not in the supported set: ${_keyCodes.keys.toList()}',
      );
    }
    await connection.send('Input.dispatchKeyEvent', {
      'type': 'keyDown',
      'key': key,
      'code': key,
      'windowsVirtualKeyCode': code,
    });
    await connection.send('Input.dispatchKeyEvent', {
      'type': 'keyUp',
      'key': key,
      'code': key,
      'windowsVirtualKeyCode': code,
    });
  }

  /// Closes the page target and the underlying connection.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final ws = connection;
    try {
      await ws.send('Target.closeTarget', {'targetId': target.id});
    } on Object {
      // The target may already be gone; connection close is what matters.
    }
    await ws.close();
  }

  void _ensureOpen() {
    if (_closed || connection.isClosed) {
      throw StateError('CdpPage is closed');
    }
  }

  Future<AxBounds> _resolveRect(String css) async {
    final value = await evaluate(
      'JSON.stringify((() => { const el = document.querySelector'
      '(${_jsString(css)}); if (!el) return null; '
      'const r = el.getBoundingClientRect(); '
      'return {x: r.x, y: r.y, width: r.width, height: r.height}; })())',
    );
    if (value is! String || value.isEmpty || value == 'null') {
      throw ProtocolException(
        'element not found for selector: $css',
        details: {'selector': css},
      );
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw ProtocolException(
        'unexpected rect payload for selector: $css',
        details: {'selector': css},
      );
    }
    return AxBounds(
      left: (decoded['x']! as num).toDouble(),
      top: (decoded['y']! as num).toDouble(),
      width: (decoded['width']! as num).toDouble(),
      height: (decoded['height']! as num).toDouble(),
    );
  }
}

List<AxNode> _buildTree(List<Map<String, Object?>> raw) {
  final byId = <String, Map<String, Object?>>{
    for (final node in raw)
      if (node['nodeId'] is String) node['nodeId']! as String: node,
  };
  final hasParent = <String>{};
  for (final node in raw) {
    for (final childId in node['childIds'] as List<Object?>? ?? const []) {
      if (childId is String) hasParent.add(childId);
    }
  }
  /// Builds (and splices) the subtree under [id].
  ///
  /// Ignored wrapper nodes (role `none`, `ignored: true` — layout
  /// containers Chromium does not expose) are spliced out rather than
  /// dropped: returning `null` for them orphaned the entire subtree
  /// beneath, collapsing real pages down to their RootWebArea.
  List<AxNode> build(String id) {
    final node = byId[id];
    if (node == null) return const [];
    final childIds = (node['childIds'] as List<Object?>? ?? const [])
        .whereType<String>();
    if (node['ignored'] == true) {
      return [for (final childId in childIds) ...build(childId)];
    }
    final role =
        (node['role'] as Map<String, Object?>?)?['value'] as String? ??
        'generic';
    final name = (node['name'] as Map<String, Object?>?)?['value'] as String?;
    final value =
        (node['value'] as Map<String, Object?>?)?['value'] as String?;
    final boundsJson = node['bounds'] as Map<String, Object?>?;
    final children = [
      for (final childId in childIds) ...build(childId),
    ];
    return [
      AxNode(
        role: role,
        name: name,
        value: value,
        bounds: boundsJson == null
            ? null
            : AxBounds(
                left: (boundsJson['x']! as num).toDouble(),
                top: (boundsJson['y']! as num).toDouble(),
                width: (boundsJson['width']! as num).toDouble(),
                height: (boundsJson['height']! as num).toDouble(),
              ),
        children: children,
      ),
    ];
  }

  return [
    for (final id in byId.keys)
      if (!hasParent.contains(id)) ...build(id),
  ];
}

String _jsString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

const _keyCodes = <String, int>{
  'Enter': 13,
  'Tab': 9,
  'Escape': 27,
  'Backspace': 8,
  'ArrowLeft': 37,
  'ArrowUp': 38,
  'ArrowRight': 39,
  'ArrowDown': 40,
};
