import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';
import 'cdp_discovery.dart';
import 'cdp_page.dart';

/// [AutomationDriver] over a CDP page: the observe/act/verify loop for
/// Chromium-based browsers and webviews.
///
/// Surface actions (`InvokeAction`) compose through the page's
/// `window.__mcpActions` registry — a convention, not a framework: any
/// web surface (Jaspr, plain JS, Flutter web, a design system's storybook)
/// publishes named handlers and this driver lists and invokes them.
/// Handlers may be async; a JS rejection surfaces as the rejection's
/// message. Action *results* are dropped by the observe/act/verify
/// contract — a handler that wants to report state writes the surface
/// (or a probe slot) and the caller observes.
class CdpDriver implements AutomationDriver, AutomationActionCatalog {
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
  Future<List<SurfaceActionDescriptor>> actions() async {
    final raw = await _page.evaluate(
      'Object.entries(window.__mcpActions ?? {}).map(([name, action]) => '
      '({name: name, description: (action && action.description) || "", '
      'inputSchema: (action && action.schema) || null}))',
    );
    return [
      if (raw is List<Object?>)
        for (final entry in raw)
          if (SurfaceActionDescriptor.fromJson(entry)
              case final descriptor?) descriptor,
    ];
  }

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
        if (css != null) {
          await _page.type(text, css: css, submit: submit);
        } else {
          // Focused-element entry, background-window safe: per-key
          // dispatchKeyEvent events land nowhere without OS focus
          // (measured — the field stayed empty, document.hasFocus()
          // false), while insertText writes the caret directly.
          await _page.bringToFront();
          await _page.insertText(text);
          if (submit) await _page.keyPress('Enter');
        }
      case KeyPressAction(:final key):
        await _page.keyPress(key);
      case ScrollAction(:final direction, :final distance):
        await _page.scroll(
          direction: direction,
          distance: distance ?? 300,
        );
      case EvaluateAction(:final expression):
        await _page.evaluate(expression);
      case InvokeAction(:final name, :final args):
        await _invokeSurfaceAction(name, args);
    }
  }

  /// Dispatches one `window.__mcpActions` handler and awaits its result.
  Future<void> _invokeSurfaceAction(
    final String name,
    final Map<String, Object?> args,
  ) async {
    final nameJson = jsonEncode(name);
    final argsJson = jsonEncode(args);
    await _page.evaluateAsync(
      '(async () => {'
      'const action = (window.__mcpActions ?? {})[$nameJson];'
      'if (!action || typeof action.invoke !== "function") {'
      'throw new Error("unknown surface action: $name");}'
      'await action.invoke($argsJson);'
      'return {ok: true};'
      '})()',
    );
  }

  /// Resolves role/name locators to a click.
  ///
  /// Two resolution paths, tried per attempt with a FRESH snapshot each
  /// time (Flutter web replaces semantics DOM nodes as the tree updates,
  /// so a `backendDOMNodeId` can be dead the moment it is issued — the
  /// actionability probe then reports `detached` forever):
  ///
  /// 1. The AX-snapshot path: match by exact role/name, resolve the
  ///    node's `backendDOMNodeId` to actionable bounds, click the
  ///    center. Works everywhere the AX cache is trustworthy.
  /// 2. The live-DOM path ([CdpPage.resolveNamedRect]): find the element
  ///    by aria-label/text content in the current DOM — Flutter web's
  ///    `flt-semantics` included — and click its center. Last match
  ///    wins, so a dialog's field beats page chrome.
  ///
  /// First match in snapshot order wins on path 1; exact name first,
  /// then contains, on path 2 (Flutter tiles concatenate title + hint
  /// into one accessible name).
  Future<void> _clickSemantic({String? role, String? name}) async {
    if (role == null && name == null) {
      throw const DriverUnsupportedException(
        'semantic click needs a role, a name, or both',
      );
    }
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
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
        if (match != null) {
          final backendNodeId =
              int.tryParse(match.attributes['cdp.backendDOMNodeId'] ?? '');
          if (backendNodeId != null) {
            final bounds = await _page.resolveNodeRect(backendNodeId);
            await _page.clickAt(bounds.center.$1, bounds.center.$2);
            return;
          }
        }
      } on ProtocolException catch (error) {
        // Stale backend id / not actionable — fall through to the
        // live-DOM path with a fresh snapshot next attempt.
        lastError = error;
      }
      if (name != null) {
        try {
          final bounds = await _page.resolveNamedRect(
            name,
            role: role,
            match: NameMatch.exact,
          );
          await _page.clickAt(bounds.center.$1, bounds.center.$2);
          return;
        } on ElementNotFoundException {
          // Absent from the live DOM too — the target is genuinely
          // gone; retrying cannot conjure it. Refuse with the locator
          // named.
          rethrow;
        } on ProtocolException catch (error) {
          lastError = error;
          if (attempt < 3) {
            try {
              final bounds = await _page.resolveNamedRect(
                name,
                role: role,
                match: NameMatch.contains,
              );
              await _page.clickAt(bounds.center.$1, bounds.center.$2);
              return;
            } on ProtocolException catch (error2) {
              lastError = error2;
            }
          }
        }
      }
    }
    throw ProtocolException(
      'semantic click "$role"/"$name" never landed after 3 attempts '
      '(last error: $lastError)',
      details: {'role': ?role, 'name': ?name},
    );
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
