/// Error codes for raw Steamworks failures.
enum SteamRawErrorCode {
  unsupportedPlatform,
  libraryNotFound,
  dynamicLibraryOpenFailed,
  symbolNotFound,
  invocationFailed,
}

/// Exception thrown by raw Steamworks loading and binding code.
final class SteamRawException implements Exception {
  const SteamRawException({
    required this.code,
    required this.message,
    this.symbol,
    this.cause,
  });

  final SteamRawErrorCode code;
  final String message;
  final String? symbol;
  final Object? cause;

  @override
  String toString() {
    final symbolPart = symbol == null ? '' : ' symbol=$symbol';
    final causePart = cause == null ? '' : ' cause=$cause';
    return 'SteamRawException(code: $code,$symbolPart message: $message$causePart)';
  }
}
