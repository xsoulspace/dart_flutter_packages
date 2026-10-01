import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';
import 'cdp_discovery.dart';
import 'cdp_page.dart';

/// [AutomationDriver] over a CDP page: the observe/act/verify loop for
/// Chromium-based browsers and webviews.
class CdpDriver implements AutomationDriver {
  /// Creates a driver over an attached [CdpPage].
  CdpDriver(this._page);

  final CdpPage _page;
  bool _closed = false;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    screencast: true,
    a11yTree: true,
    inputSynthesis: true,
    evaluate: true,
  );

  /// The underlying page facade (screencast sources attach through it).
  CdpPage get page => _page;

  @override
  Future<Snapshot> snapshot() => _page.accessibilitySnapshot();

  @override
  Future<void> perform(AutomationAction action) async {
    switch (action) {
      case NavigateAction(:final url):
        await _page.navigate(url);
      case ClickAction(:final css, :final role, :final name):
        if (css != null) {
          await _page.click(css: css);
        } else {
          await _clickSemantic(role: role, name: name);
        }
      case TypeAction(:final text, :final css, :final submit):
        await _page.type(text, css: css, submit: submit);
      case KeyPressAction(:final key):
        await _page.keyPress(key);
      case ScrollAction(:final direction, :final distance):
        await _page.scroll(
          direction: direction,
          distance: distance ?? 300,
        );
      case EvaluateAction(:final expression):
        await _page.evaluate(expression);
    }
  }

  /// Resolves role/name locators through the semantic snapshot: the
  /// matched node's CDP `backendDOMNodeId` resolves to a DOM node, which
  /// is hit-checked and clicked at its center. First match in snapshot
  /// order wins (exact role and name equality).
  Future<void> _clickSemantic({String? role, String? name}) async {
    final snapshot = await _page.accessibilitySnapshot();
    AxNode? match;
    for (final node in snapshot.nodes) {
      final roleOk = role == null || node.role == role;
      final nameOk = name == null || node.name == name;
      if (roleOk && nameOk) {
        match = node;
        break;
      }
    }
    if (match == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name!,
      );
    }
    final backendNodeId =
        int.tryParse(match.attributes['cdp.backendDOMNodeId'] ?? '');
    if (backendNodeId == null) {
      throw DriverUnsupportedException(
        'semantic node (${match.role} "${match.name ?? ''}") carries no '
        'cdp.backendDOMNodeId; cannot resolve click coordinates',
      );
    }
    final bounds = await _page.resolveNodeRect(backendNodeId);
    final (x, y) = bounds.center;
    await _page.clickAt(x, y);
  }

  @override
  Future<Uint8List> screenshot() => _page.screenshot();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _page.close();
  }
}

/// A browser-level session: discovery, one page attachment, and its
/// driver. Production lifecycle (spawning, leases) belongs to oka; this
/// class only consumes an already-published debug endpoint.
class CdpBrowserSession {
  CdpBrowserSession._(this.version, this.page);

  /// The `/json/version` payload the session probed at attach.
  final CdpVersionInfo version;

  /// The page facade this session drives.
  final CdpPage page;
  bool _closed = false;

  /// Probes [httpBase], picks the first target of [type], connects, and
  /// attaches. Refuses to attach when the endpoint does not answer —
  /// the borrowed-lease identity check.
  static Future<CdpBrowserSession> attach(
    Uri httpBase, {
    String type = 'page',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final version = await CdpDiscovery.requireAlive(httpBase, timeout: timeout);
    final target = await CdpDiscovery.findTarget(
      httpBase,
      type: type,
      timeout: timeout,
    );
    if (target == null || target.webSocketDebuggerUrl.isEmpty) {
      throw EndpointUnreachableException(
        'no "$type" target with a debugger URL at $httpBase',
        details: {'httpBase': httpBase.toString(), 'type': type},
      );
    }
    final connection = await CdpConnection.connect(
      Uri.parse(target.webSocketDebuggerUrl),
      timeout: timeout,
    );
    final page = await CdpPage.attach(connection, target);
    return CdpBrowserSession._(version, page);
  }

  /// A driver over the attached page.
  CdpDriver get driver => CdpDriver(page);

  /// Closes page and connection. Idempotent.
  ///
  /// For borrowed sessions (an adopted browser), prefer [detach] — it
  /// keeps the page target alive and closes only this client's socket.
  Future<void> close({bool closeTarget = true}) async {
    if (_closed) return;
    _closed = true;
    await page.close(closeTarget: closeTarget);
  }

  /// Detaches without closing the page target. The borrowed-lease
  /// teardown. Idempotent.
  Future<void> detach() => close(closeTarget: false);
}
