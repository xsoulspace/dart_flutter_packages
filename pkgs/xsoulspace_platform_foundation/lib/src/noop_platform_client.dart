import 'dart:async';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

import 'capability_registry.dart';

/// Always-available fallback client with no-op capabilities.
final class NoopPlatformClient implements PlatformClient {
  NoopPlatformClient({
    final PlatformId platformId = PlatformId.custom,
    final Iterable<PlatformCapability>? capabilities,
  }) : _platformId = platformId {
    for (final capability in capabilities ?? const <PlatformCapability>[]) {
      _registerCapability(capability);
    }
  }

  final PlatformId _platformId;
  final CapabilityRegistry _registry = CapabilityRegistry();
  final StreamController<PlatformEvent> _events =
      StreamController<PlatformEvent>.broadcast();

  @override
  PlatformId get platformId => _platformId;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    _events.add(
      PlatformEvent.now(
        name: 'noop.init',
        payload: <String, Object?>{
          'missingCapabilityBehavior': options.missingCapabilityBehavior.name,
        },
      ),
    );
    return PlatformInitResult.success(
      message: 'No-op platform client started.',
    );
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  @override
  bool supports<T extends PlatformCapability>() => _registry.supports<T>();

  @override
  T require<T extends PlatformCapability>() {
    final capability = maybe<T>();
    if (capability == null) {
      throw MissingPlatformCapabilityException(
        capabilityType: T,
        supportedCapabilities: capabilityTypes,
        behavior: MissingCapabilityBehavior.permissive,
        platformId: platformId,
      );
    }
    return capability;
  }

  @override
  T? maybe<T extends PlatformCapability>() => _registry.maybe<T>();

  @override
  Set<Type> get capabilityTypes => _registry.types;

  @override
  Stream<PlatformEvent> get events => _events.stream;

  void _registerCapability(final PlatformCapability capability) {
    _registry.registerDynamic(capability.runtimeType, capability);
  }
}
