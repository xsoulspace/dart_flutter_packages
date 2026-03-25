final class VoskRawException implements Exception {
  const VoskRawException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'VoskRawException($code): $message${details == null ? '' : ' [$details]'}';
}
