import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';
import 'cdp_discovery.dart';
import 'cdp_driver.dart';
import 'cdp_page.dart';

/// A browser-level session over one WebSocket: target enumeration,
/// page creation, and flat-session multiplexing — the multi-tab verbs.
///
/// Boundary (ADR 0037): this class owns protocol, not process. It never
/// launches a browser and never kills one — [close] only drops this
/// client's socket, leaving an adopted browser untouched; deciding
/// *whether* to open or close targets is the orchestrator's (oka's)
/// policy, these are the verbs it would drive.
///
/// There is deliberately **no active-page state**: every flat-session
/// page is an independent `CdpPage` handle, so "switching tabs" means
/// using another handle — [switchTo] only spells that as a verb by
/// returning the driver for the page you name, mutating nothing.
final class CdpBrowser {
  CdpBrowser._(this._connection, this.version) {
    _connection.on('Target.targetDestroyed').listen((event) {
      final targetId = event.params['targetId'];
      if (targetId is! String) return;
      final page = _pagesByTarget.remove(targetId);
      if (page == null) return;
      _pages.remove(page);
      page.markClosed();
    });
  }

  final CdpConnection _connection;
  final List<CdpPage> _pages = [];
  final Map<String, CdpPage> _pagesByTarget = {};

  /// The `/json/version` payload probed at connect.
  final CdpVersionInfo version;

  /// Connects to the browser-level debugger endpoint
  /// (`webSocketDebuggerUrl` from `/json/version`).
  static Future<CdpBrowser> connect(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final version = await CdpDiscovery.requireAlive(httpBase, timeout: timeout);
    final wsUrl = version.webSocketDebuggerUrl;
    if (wsUrl.isEmpty) {
      throw EndpointUnreachableException(
        'no browser-level debugger URL advertised at $httpBase',
        details: {'httpBase': httpBase.toString()},
      );
    }
    final connection = await CdpConnection.connect(
      Uri.parse(wsUrl),
      timeout: timeout,
    );
    return CdpBrowser._(connection, version);
  }

  /// Attached pages, oldest first.
  List<CdpPage> get pages => List.unmodifiable(_pages);

  /// Creates a new page target (default `about:blank`) and attaches to
  /// it over a flat session.
  Future<CdpPage> openPage({Uri? url}) async {
    final result = await _connection.send('Target.createTarget', {
      'url': url?.toString() ?? 'about:blank',
    });
    final targetId = result['targetId'];
    if (targetId is! String) {
      throw ProtocolException(
        'Target.createTarget returned no targetId',
        details: {'result': result},
      );
    }
    return _attach(targetId, initialUrl: url);
  }

  /// Attaches to an existing page target by id.
  Future<CdpPage> attachTarget(String targetId) => _attach(targetId);

  /// Attaches to the first page target the browser reports — the
  /// single-tab convenience, parity with `CdpBrowserSession.attach`.
  Future<CdpPage> attachFirstPage() async {
    final result = await _connection.send('Target.getTargets');
    final infos = result['targetInfos'] as List<Object?>? ?? const [];
    for (final info in infos) {
      if (info is! Map<String, Object?>) continue;
      if (info['type'] != 'page') continue;
      final targetId = info['targetId'];
      if (targetId is! String) continue;
      return _attach(targetId);
    }
    throw EndpointUnreachableException(
      'no page target exists at this browser',
      details: {'targets': infos.length},
    );
  }

  Future<CdpPage> _attach(String targetId, {Uri? initialUrl}) async {
    final result = await _connection.send('Target.attachToTarget', {
      'targetId': targetId,
      'flatten': true,
    });
    final sessionId = result['sessionId'];
    if (sessionId is! String) {
      throw ProtocolException(
        'Target.attachToTarget returned no sessionId',
        details: {'targetId': targetId},
      );
    }
    final target = CdpTargetInfo(
      id: targetId,
      type: 'page',
      url: initialUrl?.toString() ?? '',
      title: '',
      webSocketDebuggerUrl: '',
    );
    final page = await CdpPage.attach(
      _connection.forSession(sessionId),
      target,
    );
    _pages.add(page);
    _pagesByTarget[targetId] = page;
    return page;
  }

  /// The driver for [page], as the "switch tab" verb: flat-session
  /// pages have no shared active state, so switching means operating on
  /// the named page's handle. Throws [ArgumentError] for a page this
  /// browser did not open or attach.
  CdpDriver switchTo(CdpPage page) {
    if (!_pages.contains(page)) {
      throw ArgumentError.value(
        page,
        'page',
        'not a page of this browser; open or attach it first',
      );
    }
    return CdpDriver(page);
  }

  /// Closes a page target and forgets its facade.
  Future<void> closePage(CdpPage page) async {
    await _connection.send('Target.closeTarget', {'targetId': page.target.id});
    _pages.remove(page);
    _pagesByTarget.remove(page.target.id);
    page.markClosed();
  }

  /// Drops this client's socket and marks every attached page dead. The
  /// browser itself is left running — this package never stops a
  /// (borrowed) browser process. Idempotent.
  Future<void> close() async {
    for (final page in List.of(_pages)) {
      page.markClosed();
    }
    _pages.clear();
    _pagesByTarget.clear();
    await _connection.close();
  }
}
