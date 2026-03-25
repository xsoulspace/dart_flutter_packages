/// Generic platform event emitted by a [PlatformClient].
final class PlatformEvent {
  const PlatformEvent({
    required this.name,
    required this.timestamp,
    this.payload = const <String, Object?>{},
  });

  factory PlatformEvent.now({
    required final String name,
    final Map<String, Object?> payload = const <String, Object?>{},
  }) {
    return PlatformEvent(
      name: name,
      timestamp: DateTime.now().toUtc(),
      payload: payload,
    );
  }

  final String name;
  final DateTime timestamp;
  final Map<String, Object?> payload;
}
