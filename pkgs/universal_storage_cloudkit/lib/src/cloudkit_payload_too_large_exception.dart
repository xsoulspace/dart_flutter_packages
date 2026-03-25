/// Thrown when encoded payload exceeds CloudKit inline record constraints.
class CloudKitPayloadTooLargeException implements Exception {
  const CloudKitPayloadTooLargeException({
    required this.path,
    required this.payloadBytes,
    required this.maxInlineBytes,
  });

  final String path;
  final int payloadBytes;
  final int maxInlineBytes;

  String get message =>
      'CloudKit inline payload too large for "$path": '
      '$payloadBytes bytes > $maxInlineBytes bytes.';

  @override
  String toString() => 'CloudKitPayloadTooLargeException: $message';
}
