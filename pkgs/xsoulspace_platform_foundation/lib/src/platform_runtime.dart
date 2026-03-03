import 'dart:async';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

import 'capability_registry.dart';
import 'noop_platform_client.dart';
import 'platform_adapter_factory.dart';
import 'platform_start_result.dart';

/// Selects exactly one active platform client by ordered priority.
final class PlatformRuntime {
  PlatformRuntime({
    required final List<PlatformAdapterFactory> factories,
    this.initOptions = const PlatformInitOptions(),
    final Iterable<PlatformCapability> permissiveFallbackCapabilities =
        const <PlatformCapability>[],
    final PlatformClient? fallbackClient,
  }) : _factories = List<PlatformAdapterFactory>.unmodifiable(factories),
       _fallbackClient = fallbackClient {
    for (final capability in permissiveFallbackCapabilities) {
      _fallbackRegistry.registerDynamic(capability.runtimeType, capability);
    }
  }

  final List<PlatformAdapterFactory> _factories;
  final CapabilityRegistry _fallbackRegistry = CapabilityRegistry();
  final PlatformClient? _fallbackClient;

  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  PlatformClient? _activeClient;
  PlatformStartResult? _startResult;
  StreamSubscription<PlatformEvent>? _clientEventsSubscription;

  final PlatformInitOptions initOptions;

  Future<PlatformStartResult> start() async {
    final existing = _startResult;
    if (existing != null) {
      return existing;
    }

    final attemptedPlatforms = <PlatformId>[];
    final orderedFactories = List<PlatformAdapterFactory>.of(_factories)
      ..sort((final a, final b) => a.priority.compareTo(b.priority));

    PlatformInitResult? activeInitResult;

    for (final factory in orderedFactories) {
      attemptedPlatforms.add(factory.platformId);

      final supported = await factory.isSupportedEnvironment();
      if (!supported) {
        continue;
      }

      final client = await factory.createClient();
      final initResult = await client.init(initOptions);
      if (initResult.isSuccess) {
        _activeClient = client;
        activeInitResult = initResult;
        break;
      }

      await client.dispose();
      if (initResult.isFailure &&
          initOptions.missingCapabilityBehavior ==
              MissingCapabilityBehavior.strict) {
        throw PlatformException(
          code: PlatformExceptionCode.initFailed,
          message:
              initResult.message ??
              'Failed to initialize platform ${factory.platformId.name}.',
          platformId: factory.platformId,
          cause: initResult.error,
        );
      }
    }

    var usedFallbackClient = false;
    if (_activeClient == null) {
      usedFallbackClient = true;
      final fallback =
          _fallbackClient ??
          NoopPlatformClient(capabilities: _fallbackRegistry.values);
      _activeClient = fallback;
      activeInitResult = await fallback.init(initOptions);
      if (!activeInitResult.isSuccess) {
        activeInitResult = PlatformInitResult.success(
          message: 'No-op fallback activated.',
        );
      }
    }

    final activeClient = _activeClient!;
    _clientEventsSubscription = activeClient.events.listen(
      _eventsController.add,
    );

    _enforceRequiredCapabilities(
      activeClient: activeClient,
      usedFallbackClient: usedFallbackClient,
    );

    final result = PlatformStartResult(
      activePlatform: activeClient.platformId,
      capabilityTypes: _capabilityTypes(activeClient),
      initResult: activeInitResult!,
      attemptedPlatforms: List<PlatformId>.unmodifiable(attemptedPlatforms),
      usedFallbackClient: usedFallbackClient,
    );
    _startResult = result;
    return result;
  }

  Future<void> stop() async {
    await _clientEventsSubscription?.cancel();
    _clientEventsSubscription = null;
    final client = _activeClient;
    _activeClient = null;
    _startResult = null;
    if (client != null) {
      await client.dispose();
    }
  }

  PlatformClient get activeClient {
    final client = _activeClient;
    if (client == null) {
      throw const PlatformException(
        code: PlatformExceptionCode.notInitialized,
        message: 'PlatformRuntime is not started. Call start() first.',
      );
    }
    return client;
  }

  PlatformId get activePlatform => activeClient.platformId;

  T require<T extends PlatformCapability>() {
    final existing = maybe<T>();
    if (existing != null) {
      return existing;
    }

    throw MissingPlatformCapabilityException(
      capabilityType: T,
      supportedCapabilities: _capabilityTypes(activeClient),
      behavior: initOptions.missingCapabilityBehavior,
      platformId: activePlatform,
    );
  }

  T? maybe<T extends PlatformCapability>() {
    final client = activeClient;
    final fromClient = client.maybe<T>();
    if (fromClient != null) {
      return fromClient;
    }

    if (initOptions.missingCapabilityBehavior ==
        MissingCapabilityBehavior.permissive) {
      return _fallbackRegistry.maybe<T>();
    }

    return null;
  }

  bool supports<T extends PlatformCapability>() {
    final client = activeClient;
    if (client.supports<T>()) {
      return true;
    }

    if (initOptions.missingCapabilityBehavior ==
        MissingCapabilityBehavior.permissive) {
      return _fallbackRegistry.supports<T>();
    }

    return false;
  }

  Stream<PlatformEvent> get events => _eventsController.stream;

  Set<Type> _capabilityTypes(final PlatformClient activeClient) {
    final types = <Type>{...activeClient.capabilityTypes};
    if (initOptions.missingCapabilityBehavior ==
        MissingCapabilityBehavior.permissive) {
      types.addAll(_fallbackRegistry.types);
    }
    return Set<Type>.unmodifiable(types);
  }

  void _enforceRequiredCapabilities({
    required final PlatformClient activeClient,
    required final bool usedFallbackClient,
  }) {
    if (initOptions.requiredCapabilities.isEmpty) {
      return;
    }

    final missing = <Type>[];
    for (final required in initOptions.requiredCapabilities) {
      final supportedByClient = activeClient.capabilityTypes.contains(required);
      final supportedByFallback =
          initOptions.missingCapabilityBehavior ==
              MissingCapabilityBehavior.permissive &&
          _fallbackRegistry.supportsType(required);
      if (!supportedByClient && !supportedByFallback) {
        missing.add(required);
      }
    }

    if (missing.isEmpty) {
      return;
    }

    if (initOptions.missingCapabilityBehavior ==
        MissingCapabilityBehavior.strict) {
      throw MissingPlatformCapabilityException(
        capabilityType: missing.first,
        supportedCapabilities: _capabilityTypes(activeClient),
        behavior: initOptions.missingCapabilityBehavior,
        platformId: activeClient.platformId,
      );
    }

    _eventsController.add(
      PlatformEvent.now(
        name: 'runtime.requiredCapabilities.missing',
        payload: <String, Object?>{
          'missing': missing.map((final e) => e.toString()).toList(),
          'usedFallbackClient': usedFallbackClient,
        },
      ),
    );
  }
}
