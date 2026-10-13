/// Stage N2 — per-file single-writer lock table shared by every gateway in
/// one squad. Real fs is shared mutable state OUTSIDE the ECS graph; two
/// actors editing one file is a race the flush coherence point does not
/// cover. The squad driver claims each task's file set for its actor; a
/// write to a file claimed by ANOTHER owner is rejected with a structured
/// ack (the model adjusts or the driver reassigns).
class FileLockTable {
  final _locks = <String, _FileLockLease>{};

  /// Claims [rel] for [owner]. Same-owner claims are re-entrant: every
  /// successful claim needs its matching [release], so an inner
  /// materializer cannot drop the router's outer review lock.
  bool claim(String rel, Object owner) {
    final current = _locks[rel];
    if (current != null) {
      if (current.owner != owner) return false;
      current.depth++;
      return true;
    }
    _locks[rel] = _FileLockLease(owner);
    return true;
  }

  void release(String rel, Object owner) {
    final current = _locks[rel];
    if (current == null || current.owner != owner) return;
    current.depth--;
    if (current.depth == 0) _locks.remove(rel);
  }

  Object? ownerOf(String rel) => _locks[rel]?.owner;
}

class _FileLockLease {
  _FileLockLease(this.owner);

  final Object owner;
  int depth = 1;
}
