import 'package:meta/meta.dart';

/// One ranked result of a lexicon query.
@immutable
final class LexiconMatch {
  const LexiconMatch({required this.word, required this.frequency});

  final String word;

  /// Normalized unigram frequency, 0..1 (1 = most frequent).
  final double frequency;

  @override
  String toString() =>
      'LexiconMatch($word, ${frequency.toStringAsFixed(3)})';

  @override
  bool operator ==(final Object other) =>
      other is LexiconMatch &&
      other.word == word &&
      other.frequency == frequency;

  @override
  int get hashCode => Object.hash(word, frequency);
}

/// The abstract dictionary: a word list with unigram frequencies and
/// ranked prefix queries.
///
/// Pure logic — no I/O, no platform calls — so every consumer (glide
/// decoders, prediction chips, tests, tools) shares one ranking
/// semantics: frequency first, shorter words breaking ties.
abstract interface class Lexicon {
  /// All words (lowercase). The iteration order is implementation
  /// defined; rely on queries, not order.
  Iterable<String> get words;

  int get wordCount;

  /// Whether [word] (lowercased) is in the lexicon.
  bool contains(final String word);

  /// Normalized unigram frequency of [word], 0..1 (1 = most frequent).
  /// Unknown words return 0 — treat as "no prior", not "impossible".
  double frequencyOf(final String word);

  /// Words starting with [prefix] (lowercased), ranked most frequent
  /// first, shorter words breaking ties. At most [limit] results.
  List<LexiconMatch> prefixCandidates(final String prefix, {final int limit});
}
