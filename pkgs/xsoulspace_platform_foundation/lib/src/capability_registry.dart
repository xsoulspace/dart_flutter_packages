import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

/// Typed storage for capability instances.
final class CapabilityRegistry {
  CapabilityRegistry({final Iterable<PlatformCapability> seed = const []}) {
    for (final capability in seed) {
      registerDynamic(capability.runtimeType, capability);
    }
  }

  final Map<Type, PlatformCapability> _capabilities =
      <Type, PlatformCapability>{};

  void register<T extends PlatformCapability>(final T capability) {
    _capabilities[T] = capability;
  }

  void registerDynamic(final Type type, final PlatformCapability capability) {
    _capabilities[type] = capability;
  }

  bool supports<T extends PlatformCapability>() => maybe<T>() != null;

  bool supportsType(final Type type) => _capabilities.containsKey(type);

  T? maybe<T extends PlatformCapability>() {
    final direct = _capabilities[T];
    if (direct is T) {
      return direct;
    }

    for (final capability in _capabilities.values) {
      if (capability is T) {
        return capability;
      }
    }
    return null;
  }

  PlatformCapability? maybeType(final Type type) => _capabilities[type];

  Set<Type> get types => Set<Type>.unmodifiable(_capabilities.keys);

  Iterable<PlatformCapability> get values => _capabilities.values;
}
