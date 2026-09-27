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
  DriverCapabilities get capabilities => DriverCapabilities.full;

  /// The underlying page facade (screencast sources attach through it).
  CdpPage get page => _page;

  @override
  Future<Snapshot> snapshot() => _page.accessibilitySnapshot();

  @override
  Future<void> perform(AutomationAction action) async {
    switch (action) {
      case NavigateAction(:final url):
        await _page.navigate(url);
      case ClickAction(:final css):
        if (css == null) {
          throw const DriverUnsupportedException(
            'CdpDriver.click needs a css selector; role/name locators '
            'require a semantic index (use snapshot() first)',
          );
        }
        await _page.click(css: css);
      case TypeAction(:final text, :final css, :final submit):
        await _page.type(text, css: css, submit: submit);
      case KeyPressAction(:final key):
        await _page.keyPress(key);
      case EvaluateAction(:final expression):
        await _page.evaluate(expression);
    }
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
  CdpBrowserSession._(this.version, this._connection, this.page);

  final CdpVersionInfo version;
  final CdpPage page;
  final CdpConnection _connection;
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
    return CdpBrowserSession._(version, connection, page);
  }

  /// A driver over the attached page.
  CdpDriver get driver => CdpDriver(page);

  /// Closes page and connection. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }
}
