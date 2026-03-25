import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

/// Runtime startup result.
final class PlatformStartResult {
  const PlatformStartResult({
    required this.activePlatform,
    required this.capabilityTypes,
    required this.initResult,
    required this.attemptedPlatforms,
    required this.usedFallbackClient,
  });

  final PlatformId activePlatform;
  final Set<Type> capabilityTypes;
  final PlatformInitResult initResult;
  final List<PlatformId> attemptedPlatforms;
  final bool usedFallbackClient;
}
