import 'package:meta/meta.dart';

/// Collision-free unique id generation.
///
/// Timestamp alone collides when ids are created within the same microsecond
/// (e.g. spawning N actors in a loop), so a process-wide monotonic counter is
/// mixed in. Deterministic — no external dependency, works on all platforms.
int _idCounter = 0;
@internal
String nextId(String prefix) {
  final count = _idCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$count';
}
