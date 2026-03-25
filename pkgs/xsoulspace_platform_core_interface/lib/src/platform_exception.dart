import 'missing_capability_behavior.dart';
import 'platform_id.dart';

/// Error code for platform runtime exceptions.
enum PlatformExceptionCode {
  notInitialized,
  initFailed,
  missingCapability,
  unsupportedEnvironment,
  invalidConfiguration,
  internal,
}

/// Base exception raised by platform runtime and adapters.
class PlatformException implements Exception {
  const PlatformException({
    required this.code,
    required this.message,
    this.platformId,
    this.cause,
  });

  final PlatformExceptionCode code;
  final String message;
  final PlatformId? platformId;
  final Object? cause;

  @override
  String toString() {
    final platformPart = platformId == null ? '' : ', platform: $platformId';
    final causePart = cause == null ? '' : ', cause: $cause';
    return 'PlatformException(code: $code$platformPart, message: $message$causePart)';
  }
}

/// Thrown when the requested capability is not available.
final class MissingPlatformCapabilityException extends PlatformException {
  MissingPlatformCapabilityException({
    required this.capabilityType,
    required this.supportedCapabilities,
    required this.behavior,
    super.platformId,
  }) : super(
         code: PlatformExceptionCode.missingCapability,
         message: _buildMessage(
           capabilityType: capabilityType,
           supportedCapabilities: supportedCapabilities,
           behavior: behavior,
           platformId: platformId,
         ),
       );

  final Type capabilityType;
  final Set<Type> supportedCapabilities;
  final MissingCapabilityBehavior behavior;

  static String _buildMessage({
    required final Type capabilityType,
    required final Set<Type> supportedCapabilities,
    required final MissingCapabilityBehavior behavior,
    required final PlatformId? platformId,
  }) {
    final sorted = supportedCapabilities.map((final e) => e.toString()).toList()
      ..sort();
    final platformText = platformId == null ? 'unknown' : platformId.name;
    return 'Capability $capabilityType is not supported on $platformText. '
        'Behavior: ${behavior.name}. Supported: ${sorted.join(', ')}';
  }
}
