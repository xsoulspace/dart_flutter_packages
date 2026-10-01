import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';
import 'cdp_discovery.dart';
import 'cdp_network.dart';

/// What a navigation waits for before [CdpPage.navigate] returns.
enum NavigateWait {
  /// The main frame committed (navigation confirmed, document swapping).
  commit,

  /// The `load` event fired (default — static resources settled).
  load,

  /// `DOMContentLoaded` fired (DOM parsed; long-loading images may lag).
  domContentLoaded,

  /// Load finished *and* the network sat idle (no in-flight requests,
  /// nothing moved for 500ms) — the SPA-friendly wait.
  networkIdle,
}

/// A page-level CDP facade: navigation, evaluation, accessibility
/// snapshots, screenshots, and trusted-input synthesis.
///
/// Input synthesis dispatches real `Input.dispatch*` events at resolved
/// element coordinates (not `element.click()` script calls), so the browser
/// treats them like user input. Input targets are auto-waited
/// (attached → visible → stable → hittable) before dispatch; `force`
/// skips the checks.
class CdpPage {
  CdpPage._(this.connection, this.target);

  /// The transport carrying this page's traffic: a dedicated socket
  /// ([CdpConnection]) or a browser-level flat session ([CdpFlatSession]).
  final CdpTransport connection;

  /// The page target this facade drives.
  final CdpTargetInfo target;
  int _revision = 0;
  bool _closed = false;
  CdpNetworkLog? _network;

  /// Attaches the facade: enables `Page`, `Runtime`, `Accessibility`,
  /// and `Network` domains.
  ///
  /// `Accessibility.enable` matters on real Chromium: without it the
  /// renderer keeps its AX tree uncomputed and `getFullAXTree` answers
  /// with the root node only (headless behaves this way reliably).
  /// `Network.enable` feeds the observation log (`network`) that
  /// `NavigateWait.networkIdle` counts on.
  static Future<CdpPage> attach(
    CdpTransport connection,
    CdpTargetInfo target,
  ) async {
    await connection.send('Page.enable');
    await connection.send('Runtime.enable');
    await connection.send('Accessibility.enable');
    return CdpPage._(connection, target)
      .._network = await CdpNetworkLog.attach(connection);
  }

  /// Monotonic revision; bumps on every navigation.
  int get revision => _revision;

  /// Observation-only network log (requests, statuses, in-flight count,
  /// response bodies). Enabled at attach.
  CdpNetworkLog get network {
    final log = _network;
    if (log == null) {
      throw StateError('CdpPage was constructed without a network log');
    }
    return log;
  }

  /// Whether the page target is gone or the transport is dead.
  bool get isClosed => _closed || connection.isClosed;

  /// Marks the page dead without touching the transport. Called by
  /// `CdpBrowser` when the underlying target is destroyed externally;
  /// not for general use.
  void markClosed() => _closed = true;

  /// When the last observation (`accessibilitySnapshot`) completed, or
  /// `null` if none has happened yet. Behavioral dispatch enforces
  /// reaction floors against this timestamp; navigation clears it.
  DateTime? get lastObservationAt => _lastObservationAt;
  DateTime? _lastObservationAt;

  /// Navigates the page and waits per [waitUntil].
  ///
  /// Correctness contract: navigation failures surface as typed errors —
  /// CDP answers `Page.navigate` successfully with an `errorText` field
  /// (e.g. `ERR_NAME_NOT_RESOLVED`), so the response is inspected and a
  /// `ProtocolException` thrown instead of waiting out the timeout. The
  /// commit wait matches the `loaderId` returned for this navigation and
  /// ignores subframe events, so an iframe finishing early cannot resolve
  /// a main frame navigation. [NavigateWait.networkIdle] additionally
  /// requires the network to sit quiet (no in-flight requests, nothing
  /// moved for 500ms).
  Future<void> navigate(
    Uri url, {
    NavigateWait waitUntil = NavigateWait.load,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureOpen();
    // Subscribe BEFORE sending: the socket delivers the result and the
    // event in order, but a listener registered after the response would
    // miss the event on the broadcast stream.
    var loaderId = '';
    var committed = false;
    var loaded = false;
    var domContentLoaded = false;
    final stage = Completer<void>();
    void check() {
      if (stage.isCompleted) return;
      final ready = switch (waitUntil) {
        NavigateWait.commit => committed,
        NavigateWait.load => loaded,
        NavigateWait.domContentLoaded => domContentLoaded || loaded,
        NavigateWait.networkIdle => loaded || domContentLoaded,
      };
      if (ready) stage.complete();
    }

    late final List<StreamSubscription<CdpEvent>> subscriptions;
    subscriptions = [
      connection.on('Page.frameNavigated').listen((event) {
        final frame = event.params['frame'] as Map<String, Object?>?;
        if (frame == null || frame.containsKey('parentId')) return;
        final frameLoader = frame['loaderId'];
        final matches = loaderId.isEmpty ||
            frameLoader is! String ||
            frameLoader.isEmpty ||
            frameLoader == loaderId;
        if (matches) committed = true;
        check();
      }),
      connection.on('Page.loadEventFired').listen((_) {
        loaded = true;
        check();
      }),
      connection.on('Page.domContentEventFired').listen((_) {
        domContentLoaded = true;
        check();
      }),
    ];
    final watch = Stopwatch()..start();
    try {
      final result = await connection.send(
        'Page.navigate',
        {'url': url.toString()},
        timeout,
      );
      final errorText = result['errorText'];
      if (errorText is String && errorText.isNotEmpty) {
        throw ProtocolException(
          'navigation failed: $errorText',
          details: {'url': url.toString(), 'errorText': errorText},
        );
      }
      final resultLoader = result['loaderId'];
      if (resultLoader is String) loaderId = resultLoader;
      check();
      await stage.future.timeout(timeout - watch.elapsed);
      if (waitUntil == NavigateWait.networkIdle) {
        await network.waitIdle(timeout: timeout - watch.elapsed);
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
    _revision++;
    _lastObservationAt = null;
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
  /// are rebuilt into a hierarchy via CDP `childIds`. Each node's CDP
  /// `backendDOMNodeId` survives in
  /// `attributes['cdp.backendDOMNodeId']` — the handle semantic locators
  /// resolve against.
  Future<Snapshot> accessibilitySnapshot() async {
    _ensureOpen();
    final result = await connection.send('Accessibility.getFullAXTree');
    _lastObservationAt = DateTime.now();
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

  /// Clicks the element at [css] by dispatching mouse events at its
  /// center, after it becomes actionable (attached → visible → stable →
  /// hittable). [force] skips the checks (coords come from the first
  /// existing rect); a missing element always refuses.
  Future<void> click({
    required String css,
    Duration timeout = const Duration(seconds: 10),
    bool force = false,
  }) async {
    _ensureOpen();
    final rect = await resolveRect(css, timeout: timeout, force: force);
    final (x, y) = rect.center;
    await clickAt(x, y);
  }

  /// Dispatches a click at explicit viewport coordinates: a move to the
  /// point, then press + release (hover states see the pointer arrive).
  Future<void> clickAt(double x, double y) async {
    _ensureOpen();
    await connection.send('Input.dispatchMouseEvent', {
      'type': 'mouseMoved',
      'x': x,
      'y': y,
    });
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

  /// Wheels the page by [distance] logical pixels in [direction]
  /// (`up`, `down`, `left`, `right`), dispatched at the viewport center.
  Future<void> scroll({
    String direction = 'down',
    double distance = 300,
  }) async {
    _ensureOpen();
    final viewport = await evaluate(
      "JSON.stringify({w: window.innerWidth, h: window.innerHeight})",
    );
    int? width;
    int? height;
    try {
      final decoded =
          jsonDecode(viewport as String) as Map<String, Object?>;
      width = (decoded['w'] as num?)?.toInt();
      height = (decoded['h'] as num?)?.toInt();
    } on FormatException {
      // Keep the fallback center below.
    }
    final (x, y) = (
      (width ?? 800) / 2,
      (height ?? 600) / 2,
    );
    final (deltaX, deltaY) = switch (direction.toLowerCase()) {
      'up' => (0.0, -distance),
      'down' => (0.0, distance),
      'left' => (-distance, 0.0),
      'right' => (distance, 0.0),
      _ => throw ProtocolException(
        'unknown scroll direction "$direction" '
        '(use up, down, left, right)',
      ),
    };
    await connection.send('Input.dispatchMouseEvent', {
      'type': 'mouseWheel',
      'x': x,
      'y': y,
      'deltaX': deltaX,
      'deltaY': deltaY,
    });
  }

  /// Focuses [css] (when given), waits for it to become actionable, then
  /// types [text] as real per-key events (printable ASCII) with
  /// IME-style character events as the non-ASCII fallback — the same
  /// lowering the behavioral path uses. [submit] presses Enter.
  Future<void> type(
    String text, {
    String? css,
    bool submit = false,
    Duration timeout = const Duration(seconds: 10),
    bool force = false,
  }) async {
    _ensureOpen();
    if (css != null) {
      await resolveRect(css, timeout: timeout, force: force);
      await evaluate('document.querySelector(${_jsString(css)})?.focus()');
    }
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final keyCode = rune >= 0x20 && rune <= 0x7e
          ? printableVirtualKeyCode(ch)
          : null;
      if (keyCode == null) {
        await connection.send('Input.insertText', {'text': ch});
        continue;
      }
      await connection.send('Input.dispatchKeyEvent', {
        'type': 'keyDown',
        'key': ch,
        'code': ch,
        'windowsVirtualKeyCode': keyCode,
        'text': ch,
        'unmodifiedText': ch,
      });
      await connection.send('Input.dispatchKeyEvent', {
        'type': 'keyUp',
        'key': ch,
        'code': ch,
        'windowsVirtualKeyCode': keyCode,
      });
    }
    if (submit) await keyPress('Enter');
  }

  /// Presses a named key. Supported: `Enter`, `Tab`, `Escape`,
  /// `Backspace`, `ArrowUp`/`Down`/`Left`/`Right`.
  Future<void> keyPress(String key) async {
    _ensureOpen();
    final code = namedVirtualKeyCode(key);
    if (code == null) {
      throw DriverUnsupportedException(
        'key "$key" is not in the supported set: Enter, Tab, Escape, '
        'Backspace, ArrowLeft, ArrowUp, ArrowRight, ArrowDown',
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
  ///
  /// For borrowed sessions (an adopted browser this process must not
  /// tear down), use [detach] instead — it closes only this client's
  /// socket and leaves the target alive. Over a flat session
  /// ([CdpFlatSession]) the connection close is a no-op; page-target
  /// lifecycle then belongs to `CdpBrowser.closePage`.
  Future<void> close({bool closeTarget = true}) async {
    if (_closed) return;
    _closed = true;
    await _network?.dispose();
    final ws = connection;
    if (closeTarget) {
      try {
        await ws.send('Target.closeTarget', {'targetId': target.id});
      } on Object {
        // The target may already be gone; connection close is what
        // matters.
      }
    }
    await ws.close();
  }

  /// Closes only this client's connection; the target stays alive. The
  /// borrowed-lease teardown.
  Future<void> detach() => close(closeTarget: false);

  void _ensureOpen() {
    if (isClosed) {
      throw StateError('CdpPage is closed');
    }
  }

  /// Resolves [css] to viewport-space bounds once the element is
  /// actionable: attached → visible → stable (two identical consecutive
  /// rects) → center-point hittable, polling every 50ms until [timeout].
  /// [force] returns the first existing rect without the checks.
  Future<AxBounds> resolveRect(
    String css, {
    Duration timeout = const Duration(seconds: 10),
    bool force = false,
  }) =>
      _waitForActionableRect(
        probe: () => evaluate(_elementProbe(_cssProbeBody(css))),
        label: css,
        timeout: timeout,
        force: force,
      );

  /// Resolves a semantic-snapshot node (by CDP `backendDOMNodeId`, the
  /// handle `accessibilitySnapshot` records) to actionable viewport
  /// bounds, with the same checks as [resolveRect].
  Future<AxBounds> resolveNodeRect(
    int backendNodeId, {
    Duration timeout = const Duration(seconds: 10),
    bool force = false,
  }) {
    Future<Object?> probe() async {
      try {
        final resolved = await connection.send(
          'DOM.resolveNode',
          {'backendNodeId': backendNodeId},
        );
        final objectId =
            (resolved['object'] as Map<String, Object?>?)?['objectId'];
        if (objectId is! String) return null;
        final result = await connection.send('Runtime.callFunctionOn', {
          'objectId': objectId,
          'functionDeclaration': _nodeProbeFunction,
          'returnByValue': true,
        });
        return (result['result'] as Map<String, Object?>?)?['value'];
      } on ProtocolException {
        // Stale node handle — report detached; the poll keeps trying
        // with a fresh resolve until the deadline.
        return null;
      }
    }

    return _waitForActionableRect(
      probe: probe,
      label: 'backend-node-$backendNodeId',
      timeout: timeout,
      force: force,
    );
  }

  /// The shared actionability loop: probe → decode → (detached | empty |
  /// hidden | occluded | ready), requiring two identical consecutive
  /// rects before declaring stability.
  Future<AxBounds> _waitForActionableRect({
    required Future<Object?> Function() probe,
    required String label,
    required Duration timeout,
    required bool force,
  }) async {
    _ensureOpen();
    final deadline = DateTime.now().add(timeout);
    String? previousKey;
    var lastState = 'unknown';
    while (true) {
      var decoded = const <String, Object?>{'state': 'detached'};
      final value = await probe();
      if (value is String && value.isNotEmpty && value != 'null') {
        final parsed = jsonDecode(value);
        if (parsed is Map<String, Object?>) decoded = parsed;
      }
      final state = decoded['state'] as String?;
      if (state == null) {
        // Legacy payload shape (rect + hitOk) from canned endpoints.
        if (decoded['hitOk'] == true) return _boundsFrom(decoded);
        lastState = 'occluded';
      } else if (state == 'detached') {
        lastState = state;
      } else if (force) {
        return _boundsFrom(decoded);
      } else if (state == 'ready') {
        final key =
            '${decoded['x']}|${decoded['y']}|'
            '${decoded['width']}|${decoded['height']}';
        if (previousKey != null && previousKey == key) {
          return _boundsFrom(decoded);
        }
        previousKey = key;
        lastState = 'stable?';
      } else {
        lastState = state;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ProtocolException(
          'element "$label" not actionable within '
          '${timeout.inMilliseconds}ms (last state: $lastState)',
          details: {'target': label, 'state': lastState},
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  AxBounds _boundsFrom(Map<String, Object?> decoded) => AxBounds(
    left: (decoded['x']! as num).toDouble(),
    top: (decoded['y']! as num).toDouble(),
    width: (decoded['width']! as num).toDouble(),
    height: (decoded['height']! as num).toDouble(),
  );
}

/// One actionability probe over a CSS-located element, as JSON.
String _cssProbeBody(String css) =>
    'const el = document.querySelector(${_jsString(css)}); '
    '${_elementProbeTail()}';

/// The element-scoped probe body parameterized over `this` (used via
/// `Runtime.callFunctionOn` for semantic nodes).
final String _nodeProbeFunction =
    'function() { return (function() { '
    'const el = this; '
    'return JSON.stringify((function() { ${_elementProbeTail()} })()); '
    '})(); }';

String _elementProbe(String body) => 'JSON.stringify((() => { $body })())';

/// Shared probe tail: [el] must be in scope. Scrolls into view, then
/// reports the actionability state plus the viewport rect.
String _elementProbeTail() =>
    'if (!el) return {state: "detached"}; '
    'el.scrollIntoView({block: "center", inline: "center"}); '
    'const r = el.getBoundingClientRect(); '
    'const rect = {x: r.x, y: r.y, width: r.width, height: r.height}; '
    'if (r.width <= 0 || r.height <= 0) '
    'return Object.assign({state: "empty"}, rect); '
    'const style = getComputedStyle(el); '
    'if (style.display === "none" || style.visibility === "hidden") '
    'return Object.assign({state: "hidden"}, rect); '
    'const cx = r.x + r.width / 2; const cy = r.y + r.height / 2; '
    'const hit = document.elementFromPoint(cx, cy); '
    'const hitOk = !!(hit && (el === hit || el.contains(hit))); '
    'return Object.assign({state: hitOk ? "ready" : "occluded"}, rect);';

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
    final backendNodeId = node['backendDOMNodeId'];
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
        attributes: {
          // The semantic-locator handle: resolves to a DOM node for
          // coordinate dispatch (see `CdpPage.resolveNodeRect`).
          if (backendNodeId is int)
            'cdp.backendDOMNodeId': backendNodeId.toString(),
        },
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
