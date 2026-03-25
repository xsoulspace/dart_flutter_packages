/// Wrapper runtime exception codes.
enum SteamExceptionCode {
  notInitialized,
  nativeUnavailable,
  invalidConfiguration,
  nativeFailure,
  timeout,
}

/// Exception raised by Steamworks wrapper runtime and services.
final class SteamException implements Exception {
  const SteamException({required this.code, required this.message, this.cause});

  final SteamExceptionCode code;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final causePart = cause == null ? '' : ' cause=$cause';
    return 'SteamException(code: $code, message: $message$causePart)';
  }
}
