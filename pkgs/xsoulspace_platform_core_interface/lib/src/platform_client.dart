import 'platform_capability.dart';
import 'platform_event.dart';
import 'platform_id.dart';
import 'platform_init.dart';

/// Runtime client for a concrete platform implementation.
abstract interface class PlatformClient {
  PlatformId get platformId;

  Future<PlatformInitResult> init(PlatformInitOptions options);

  Future<void> dispose();

  bool supports<T extends PlatformCapability>();

  T require<T extends PlatformCapability>();

  T? maybe<T extends PlatformCapability>();

  Set<Type> get capabilityTypes;

  Stream<PlatformEvent> get events;
}
