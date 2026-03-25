final class SherpaOnnxRawException implements Exception {
  const SherpaOnnxRawException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'SherpaOnnxRawException($code): $message${details == null ? '' : ' [$details]'}';
}
