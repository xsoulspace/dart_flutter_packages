final class WhisperCppRawException implements Exception {
  const WhisperCppRawException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'WhisperCppRawException($code): $message${details == null ? '' : ' [$details]'}';
}
