import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

/// Factory that probes and creates a concrete [PlatformClient].
abstract interface class PlatformAdapterFactory {
  PlatformId get platformId;

  /// Lower values are attempted first.
  int get priority;

  /// Fast environment probe to decide whether adapter can run.
  Future<bool> isSupportedEnvironment();

  /// Creates a fresh client instance.
  Future<PlatformClient> createClient();
}
