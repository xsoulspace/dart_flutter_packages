import 'dart:math' as math;

import 'lexicon.dart';

/// The default [Lexicon]: an in-memory sorted word list with a frequency
/// map, answering prefix queries through a binary-search range scan.
///
/// Comfortable to ~100k words (a range scan is O(log n + hits); the
/// final ranking sort is over the hits only). Words are lowercased and
/// deduplicated on construction; missing frequencies rank as 0.
final class ListLexicon implements Lexicon {
  ListLexicon({
    required final Iterable<String> words,
    final Map<String, double> frequencies = const <String, double>{},
  }) : _words = _normalize(words),
       _frequencies = Map<String, double>.of(frequencies);

  final List<String> _words;
  final Map<String, double> _frequencies;

  static List<String> _normalize(final Iterable<String> input) {
    final set = <String>{for (final word in input) word.toLowerCase()};
    final list = set.toList(growable: false)..sort();
    return list;
  }

  @override
  Iterable<String> get words => List.unmodifiable(_words);

  @override
  int get wordCount => _words.length;

  @override
  bool contains(final String word) {
    final probe = word.toLowerCase();
    var lo = 0;
    var hi = _words.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final comparison = _words[mid].compareTo(probe);
      if (comparison == 0) return true;
      if (comparison < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return false;
  }

  @override
  double frequencyOf(final String word) =>
      _frequencies[word.toLowerCase()] ?? 0.0;

  @override
  List<LexiconMatch> prefixCandidates(
    final String prefix, {
    final int limit = 3,
  }) {
    if (limit <= 0) return const <LexiconMatch>[];
    final probe = prefix.toLowerCase();
    // Range scan: everything from the first word >= probe that still
    // starts with it.
    var lo = _lowerBound(probe);
    final matches = <LexiconMatch>[];
    while (lo < _words.length && _words[lo].startsWith(probe)) {
      final word = _words[lo];
      matches.add(
        LexiconMatch(word: word, frequency: _frequencies[word] ?? 0.0),
      );
      lo++;
    }
    if (matches.length > 1) {
      matches.sort(_rankOrder);
    }
    return matches.take(limit).toList(growable: false);
  }

  @override
  List<LexiconMatch> fuzzyPrefixCandidates(
    final String prefix, {
    final int limit = 3,
    final int maxDistance = 1,
  }) {
    if (limit <= 0 || prefix.isEmpty) return const <LexiconMatch>[];
    final probe = prefix.toLowerCase();
    final scored = <(int, LexiconMatch)>[];
    for (final word in _words) {
      final head = word.length <= probe.length
          ? word
          : word.substring(0, probe.length);
      final distance = _boundedEditDistance(probe, head, maxDistance);
      if (distance <= maxDistance) {
        scored.add((
          distance,
          LexiconMatch(word: word, frequency: _frequencies[word] ?? 0.0),
        ));
      }
    }
    if (scored.isEmpty) return const <LexiconMatch>[];
    // Distance first (a near-exact head outranks a rough one), then the
    // family's frequency ranking.
    scored.sort((final a, final b) {
      final byDistance = a.$1.compareTo(b.$1);
      if (byDistance != 0) return byDistance;
      final byFrequency = b.$2.frequency.compareTo(a.$2.frequency);
      if (byFrequency != 0) return byFrequency;
      return a.$2.word.length.compareTo(b.$2.word.length);
    });
    return scored.take(limit).map((final entry) => entry.$2).toList(
      growable: false,
    );
  }

  /// Levenshtein distance with an early exit once the row minimum
  /// exceeds [cap] — the scan runs over the whole dictionary, so the
  /// bound is what keeps a 50k-word commit at one-shot latency.
  static int _boundedEditDistance(
    final String a,
    final String b,
    final int cap,
  ) {
    if (a == b) return 0;
    var previous = List<int>.generate(b.length + 1, (final i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, i);
      for (var j = 1; j <= b.length; j++) {
        final substitution =
            previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          substitution,
        );
      }
      if (current.reduce(math.min) > cap) return cap + 1;
      previous = current;
    }
    return previous[b.length];
  }

  /// First index whose word is >= [probe] (classic lower bound).
  int _lowerBound(final String probe) {
    var lo = 0;
    var hi = _words.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_words[mid].compareTo(probe) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _rankOrder(final LexiconMatch a, final LexiconMatch b) {
    final byFrequency = b.frequency.compareTo(a.frequency);
    if (byFrequency != 0) return byFrequency;
    final byLength = a.word.length.compareTo(b.word.length);
    if (byLength != 0) return byLength;
    return a.word.compareTo(b.word);
  }
}
