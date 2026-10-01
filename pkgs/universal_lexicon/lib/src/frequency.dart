import 'dart:math' as math;

/// Normalizes raw corpus counts into the 0..1 unigram prior the lexicon
/// and decoders consume.
///
/// The recipe for corpus lists (OpenSubtitles counts, Google Ngrams
/// volumes, …): rank on a LOG scale — word frequencies span orders of
/// magnitude and a linear map would give the top 10 words all the
/// signal. The most frequent word maps to 1.0, the least frequent to
/// [floor], everything between by log interpolation.
Map<String, double> normalizeCounts(
  final Map<String, int> counts, {
  final double floor = 0.05,
}) {
  if (counts.isEmpty) return const <String, double>{};
  var minLog = double.infinity;
  var maxLog = double.negativeInfinity;
  final logs = <String, double>{
    for (final MapEntry(key: word, value: count) in counts.entries)
      word: count <= 1 ? 0.0 : math.log(count.toDouble()),
  };
  for (final value in logs.values) {
    if (value < minLog) minLog = value;
    if (value > maxLog) maxLog = value;
  }
  final span = maxLog - minLog;
  return <String, double>{
    for (final MapEntry(key: word, value: logCount) in logs.entries)
      word: span <= 0
          ? 1.0
          : floor + (1.0 - floor) * (logCount - minLog) / span,
  };
}
