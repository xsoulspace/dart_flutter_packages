/// Facet index over the narrative graph.
///
/// A keyword → beats index that makes projection a ray-tracing query: given
/// a prompt, we look up the beats whose keywords match instead of scanning a
/// per-actor memory list. This is a derived index — beats are indexed when
/// they are written, and projection reads it functionally.
///
/// Also maintains thread membership (beatsOfThread) and per-thread sequence
/// counters so projection/scoring are O(beats-in-thread), not full-world
/// scans.
library;

import 'package:ecsly/ecsly.dart';

import 'components.dart';

class FacetIndex extends Resource {
  final Map<String, Set<Entity>> byKeyword = {};
  final Map<Entity, Set<String>> keywordsOf = {};

  /// Thread → member beats, in write order. Derived from [BelongsToThread]
  /// writes; kept here so ray-tracing is O(threads × beats-in-thread).
  final Map<Entity, List<Entity>> _beatsByThread = {};

  /// Per-thread monotonic beat sequence counters.
  final Map<Entity, int> _sequenceCounters = {};

  /// Index [beat] under [keywords] and record its thread membership.
  /// Idempotent for keywords — re-indexing a beat with the same keywords is
  /// a no-op; new keywords are unioned in.
  void indexBeat(Entity beat, Iterable<String> keywords, {Entity? thread}) {
    final owned = keywordsOf.putIfAbsent(beat, () => <String>{});
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      byKeyword.putIfAbsent(keyword, () => <Entity>{}).add(beat);
      owned.add(keyword);
    }
    if (thread != null) {
      final members = _beatsByThread.putIfAbsent(thread, () => []);
      if (!members.contains(beat)) members.add(beat);
    }
  }

  /// Union of all beats indexed under any of [keywords].
  Iterable<Entity> beatsFor(Iterable<String> keywords) {
    final out = <Entity>{};
    for (final keyword in keywords) {
      final hits = byKeyword[keyword];
      if (hits != null) out.addAll(hits);
    }
    return out;
  }

  /// The keywords currently indexed for [beat].
  Set<String> keywordsFor(Entity beat) => keywordsOf[beat] ?? <String>{};

  /// Beats belonging to [thread], in insertion order. Empty when unknown —
  /// callers fall back to graph queries only for pre-index legacy content.
  Iterable<Entity> beatsOfThread(Entity thread) =>
      _beatsByThread[thread] ?? const [];

  /// Move [beat]'s membership from [from] to [to] (thread merge).
  void moveBeatToThread(Entity beat, Entity from, Entity to) {
    final source = _beatsByThread[from];
    if (source != null) source.remove(beat);
    final target = _beatsByThread.putIfAbsent(to, () => []);
    if (!target.contains(beat)) target.add(beat);
  }

  /// Next [BeatSequence] value for [thread]. O(1) via the counter instead of
  /// scanning every sequenced beat in the world.
  int nextSequenceOf(Entity thread) => (_sequenceCounters[thread] ?? 0) + 1
    ..let((v) => _sequenceCounters[thread] = v);

  /// Remove [beat] from the index entirely.
  ///
  /// Called when a beat's thread is pruned or merged away so stale keyword
  /// hits cannot resurface pruned content in projections.
  void deindexBeat(Entity beat) {
    final owned = keywordsOf.remove(beat);
    if (owned != null) {
      for (final keyword in owned) {
        final hits = byKeyword[keyword];
        if (hits == null) continue;
        hits.remove(beat);
        if (hits.isEmpty) byKeyword.remove(keyword);
      }
    }
    for (final members in _beatsByThread.values) {
      members.remove(beat);
    }
  }

  /// Drop all entries (world teardown / scenario switch).
  void clear() {
    byKeyword.clear();
    keywordsOf.clear();
    _beatsByThread.clear();
    _sequenceCounters.clear();
  }
}

/// Index a beat into the world's [FacetIndex] under the given keywords and,
/// when known, its owning thread.
///
/// Mechanical helper — callers derive keywords from the beat's content and
/// write them here so projection can ray-trace to the beat later.
void indexBeat(
  World w,
  Entity beat,
  Iterable<String> keywords, {
  Entity? thread,
}) {
  w.getResource<FacetIndex>().indexBeat(beat, keywords, thread: thread);
}

/// Remove [beat] from the world's [FacetIndex].
///
/// Call when a beat's thread is pruned/merged so stale keyword hits cannot
/// resurface pruned content in projections.
void deindexBeat(World w, Entity beat) {
  w.getResource<FacetIndex>().deindexBeat(beat);
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
