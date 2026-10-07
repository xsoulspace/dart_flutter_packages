import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

import '../plan/plan.dart';

/// A resolved, live session: a driver over an attached endpoint.
abstract interface class ResolvedSession {
  /// The binding this session resolved.
  SessionBinding get binding;

  /// The attached driver.
  AutomationDriver get driver;

  /// The surface URL, when the transport exposes one.
  Uri? get url;

  /// The behavioral face of the driver, when the tier can honor ADR 0044
  /// profiles; `null` means profiled dispatches must fail loudly.
  BehavioralDriver? asBehavioral();

  /// Detaches: drops this client's connection, never stops the process
  /// behind it (attach-only teardown).
  Future<void> detach();
}

/// A transport named in a plan has no linked driver binding in this
/// build — loud, per the family refuse-not-degrade rule.
class TransportNotLinkedException extends AutomationException {
  /// Creates the exception for [transport].
  TransportNotLinkedException(this.transport, {required String sessionName})
    : super(
        'transport "$transport" has no linked driver in this build '
        '(session "$sessionName"); link its family package to enable it',
        details: {'transport': transport, 'session': sessionName},
      );

  @override
  String get kind => 'transportNotLinked';

  /// The unlinked transport name.
  final String transport;
}

/// Attaches plan session bindings to live drivers — lazily, cached per
/// binding (and per endpoint for ad-hoc use).
///
/// The registry is attach-only: [ResolvedSession.detach] drops the
/// client's connection and never stops the process behind it (ADR 0037
/// house rule 2; lifecycle belongs to oka).
final class SessionRegistry {
  /// Creates a registry over [bindings]; [overrides] resolve handle
  /// bindings (handle name → endpoint URI).
  SessionRegistry({
    required Map<String, SessionBinding> bindings,
    this.overrides = const {},
    this.attachTimeout = const Duration(seconds: 10),
  }) : _bindings = bindings;

  final Map<String, SessionBinding> _bindings;

  /// Handle-name → URI overrides supplied by the caller (CLI `--set`).
  final Map<String, String> overrides;

  /// Attach deadline per session.
  final Duration attachTimeout;

  final Map<String, ResolvedSession> _attached = {};
  final Map<String, ResolvedSession> _adHoc = {};

  /// Attaches (or returns the cached) session named [name].
  Future<ResolvedSession> attach(String name) async {
    final cached = _attached[name];
    if (cached != null) return cached;
    final binding = _bindings[name];
    if (binding == null) {
      throw EndpointUnreachableException(
        'unknown session "$name"',
        details: {'sessions': _bindings.keys.toList()},
      );
    }
    final resolved = await _resolve(binding);
    _attached[name] = resolved;
    return resolved;
  }

  /// Attaches (or returns the cached) ad-hoc session at [uri] — the
  /// per-call endpoint override used by MCP tools.
  Future<ResolvedSession> attachUri(Uri uri, AutomationTransport transport) {
    final key = '${transport.name}|$uri';
    final cached = _adHoc[key];
    if (cached != null) return Future.value(cached);
    return _resolve(
      SessionBinding(name: key, transport: transport, uri: uri),
    ).then((resolved) {
      _adHoc[key] = resolved;
      return resolved;
    });
  }

  Future<ResolvedSession> _resolve(SessionBinding binding) async {
    final uri = binding.resolveUri(overrides);
    if (uri == null) {
      throw EndpointUnreachableException(
        'session "${binding.name}" has no resolvable endpoint: handle '
        '"${binding.handle}" was not overridden; pass --set '
        '${binding.handle}=<uri>',
        details: {'session': binding.name, 'handle': binding.handle},
      );
    }
    switch (binding.transport) {
      case AutomationTransport.cdp:
        final session = await CdpBrowserSession.attach(uri, timeout: attachTimeout);
        return _CdpResolvedSession(binding, session);
      case AutomationTransport.webdriver:
      case AutomationTransport.vmService:
      case AutomationTransport.osAccessibility:
      case AutomationTransport.custom:
        throw TransportNotLinkedException(
          binding.transport.name,
          sessionName: binding.name,
        );
    }
  }

  /// Detaches every session this registry opened. Idempotent.
  Future<void> detachAll() async {
    for (final session in [
      ..._attached.values,
      ..._adHoc.values,
    ]) {
      await session.detach();
    }
    _attached.clear();
    _adHoc.clear();
  }
}

final class _CdpResolvedSession implements ResolvedSession {
  _CdpResolvedSession(this.binding, this.session) {
    // Track the live surface URL: the attach-time target info is a
    // snapshot and goes stale on the first navigation.
    final initial = session.page.target.url;
    _url = initial.isEmpty ? null : Uri.tryParse(initial);
    session.page.connection.on('Page.frameNavigated').listen((event) {
      final frame = event.params['frame'] as Map<String, Object?>?;
      if (frame == null || frame.containsKey('parentId')) return;
      final navigatedTo = frame['url'];
      if (navigatedTo is String && navigatedTo.isNotEmpty) {
        _url = Uri.tryParse(navigatedTo);
      }
    });
  }

  Uri? _url;

  final CdpBrowserSession session;
  BehavioralCdpDriver? _behavioral;

  @override
  final SessionBinding binding;

  @override
  AutomationDriver get driver => session.driver;

  @override
  Uri? get url => _url;

  @override
  BehavioralDriver? asBehavioral() =>
      // One behavioral face per session: pointer continuity persists
      // across a scenario's profiled steps.
      _behavioral ??= BehavioralCdpDriver(session.page);

  @override
  Future<void> detach() => session.detach();
}
