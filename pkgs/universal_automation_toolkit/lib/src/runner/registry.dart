import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_browser_webdriver/universal_browser_webdriver.dart';
import 'package:universal_driver_linux/universal_driver_linux.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';
import 'package:universal_driver_windows/universal_driver_windows.dart';

import '../plan/plan.dart';

/// Builds a live session over one resolved endpoint — the extension seam
/// of the registry. Composition roots (e.g. the instrumented Flutter
/// tier, which lives in mcp_flutter per ADR 0038's dependency direction)
/// register additional factories here without touching this package.
typedef DriverFactory = Future<ResolvedSession> Function(
  SessionBinding binding,
  Uri endpoint,
  Duration attachTimeout,
);

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
        '(session "$sessionName"); link its family package or register a '
        'DriverFactory to enable it',
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
/// Attach-only: [ResolvedSession.detach] drops the client's connection
/// and never stops the process behind it (ADR 0037 house rule 2;
/// lifecycle belongs to oka). Transport coverage: CDP, WebDriver, and
/// the OS-native tier (macOS AX / Linux AT-SPI / Windows UIA sidecar)
/// are linked; `vmService` resolves through [factories] registered by
/// composition roots (the instrumented Flutter tier lives in
/// mcp_flutter — ADR 0036 one-way direction).
final class SessionRegistry {
  /// Creates a registry over [bindings]; [overrides] resolve handle
  /// bindings (handle name → endpoint URI); [factories] extend or
  /// replace the built-in per-transport factories.
  SessionRegistry({
    required Map<String, SessionBinding> bindings,
    this.overrides = const {},
    this.attachTimeout = const Duration(seconds: 10),
    Map<AutomationTransport, DriverFactory>? factories,
    this.handleBaseDirectory,
  }) : _bindings = bindings,
       _factories = {...?factories};

  final Map<String, SessionBinding> _bindings;

  /// Handle-name → URI overrides supplied by the caller (CLI `--set`).
  final Map<String, String> overrides;

  /// Attach deadline per session.
  final Duration attachTimeout;

  /// Directory scanned for handle artifacts
  /// (`session-<name>-handle` files holding the endpoint URI), when oka
  /// (or any lifecycle owner) publishes them there; `--set` overrides
  /// win over artifacts.
  final String? handleBaseDirectory;

  final Map<AutomationTransport, DriverFactory> _factories;
  final Map<String, ResolvedSession> _attached = {};
  final Map<String, ResolvedSession> _adHoc = {};

  /// The built-in factories; exposure is read-only.
  Map<AutomationTransport, DriverFactory> get factories =>
      Map.unmodifiable(_factories);

  /// Registers (or replaces) the factory for [transport].
  void registerFactory(AutomationTransport transport, DriverFactory factory) {
    _factories[transport] = factory;
  }

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

  /// Attaches (or returns the cached) ad-hoc session on an endpoint-free
  /// transport — the OS-native tier: the macOS AX driver binds the
  /// focused application, Linux AT-SPI and Windows UIA fall back to
  /// their session defaults. The `oka:focused` sentinel marks the
  /// binding so resolution never demands a URI; a driver still reads it
  /// when an optional refinement (a11y bus address, UIA sidecar binary).
  Future<ResolvedSession> attachFocused(AutomationTransport transport) {
    final key = '${transport.name}|focused';
    final cached = _adHoc[key];
    if (cached != null) return Future.value(cached);
    return _resolve(
      SessionBinding(
        name: key,
        transport: transport,
        uri: Uri.parse('oka:focused'),
      ),
    ).then((resolved) {
      _adHoc[key] = resolved;
      return resolved;
    });
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
    final uri = resolveEndpoint(binding);
    final factory = _factories[binding.transport] ??
        _builtinFactory(binding.transport);
    if (factory == null) {
      throw TransportNotLinkedException(
        binding.transport.name,
        sessionName: binding.name,
      );
    }
    if (uri == null && !_endpointFree(binding.transport)) {
      throw EndpointUnreachableException(
        'session "${binding.name}" has no resolvable endpoint: handle '
        '"${binding.handle}" resolved to nothing; pass --set '
        '${binding.handle}=<uri>, publish the handle artifact under '
        'the handles directory, or use an endpoint-free binding',
        details: {'session': binding.name, 'handle': binding.handle},
      );
    }
    return factory(binding, uri ?? Uri.parse('oka:focused'), attachTimeout);
  }

  /// Endpoint-free transports (the macOS AX tier drives the focused
  /// application and needs no URI).
  static bool _endpointFree(AutomationTransport transport) =>
      transport == AutomationTransport.osAccessibility && Platform.isMacOS;

  /// Resolves a binding's endpoint: explicit uri, then `--set`-style
  /// overrides, then handle artifacts under [handleBaseDirectory].
  Uri? resolveEndpoint(SessionBinding binding) {
    if (binding.uri != null) return binding.uri;
    final handle = binding.handle;
    if (handle == null) return null;
    final override = overrides[handle];
    if (override != null) return Uri.tryParse(override);
    final base = handleBaseDirectory;
    if (base == null) return null;
    final artifact = File('$base/$handle');
    if (!artifact.existsSync()) return null;
    final value = artifact.readAsStringSync().trim();
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  DriverFactory? _builtinFactory(AutomationTransport transport) =>
      switch (transport) {
        AutomationTransport.cdp => _attachCdp,
        AutomationTransport.webdriver => _attachWebdriver,
        AutomationTransport.osAccessibility => _attachOsAccessibility,
        _ => null,
      };

  static Future<ResolvedSession> _attachCdp(
    SessionBinding binding,
    Uri endpoint,
    Duration timeout,
  ) async {
    final session = await CdpBrowserSession.attach(endpoint, timeout: timeout);
    return _CdpResolvedSession(binding, session);
  }

  static Future<ResolvedSession> _attachWebdriver(
    SessionBinding binding,
    Uri endpoint,
    Duration timeout,
  ) async {
    final client = WebDriverClient(endpoint);
    await client.newSession();
    return _WebdriverResolvedSession(binding, client);
  }

  static Future<ResolvedSession> _attachOsAccessibility(
    SessionBinding binding,
    Uri endpoint,
    Duration timeout,
  ) async {
    if (Platform.isMacOS) {
      return _MacosResolvedSession(binding, BehavioralMacosDriver());
    }
    if (Platform.isLinux) {
      final bus = DBusAtspiBus(
        a11yAddress: endpoint.scheme == 'unix'
            ? endpoint.path
            : null,
      );
      return _SimpleResolvedSession(binding, AtspiDriver(bus));
    }
    if (Platform.isWindows) {
      return _SimpleResolvedSession(
        binding,
        await UiaDriver.connect(
          binary: endpoint.scheme == 'file' ? endpoint.toFilePath() : null,
        ),
      );
    }
    throw TransportNotLinkedException(
      '${binding.transport.name} on ${Platform.operatingSystem}',
      sessionName: binding.name,
    );
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

/// Driver-only resolved session (no behavioral face, no URL).
final class _SimpleResolvedSession implements ResolvedSession {
  _SimpleResolvedSession(this.binding, this.driver);

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() => driver.close();
}

final class _WebdriverResolvedSession implements ResolvedSession {
  _WebdriverResolvedSession(this.binding, this.client)
    : driver = WebDriverDriver(client);

  final WebDriverClient client;

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() => client.deleteSession();
}

final class _MacosResolvedSession implements ResolvedSession {
  _MacosResolvedSession(this.binding, BehavioralMacosDriver macosDriver)
    : macosDriver = macosDriver,
      driver = macosDriver;

  @override
  final SessionBinding binding;

  final BehavioralMacosDriver macosDriver;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => macosDriver;

  @override
  Future<void> detach() => driver.close();
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
