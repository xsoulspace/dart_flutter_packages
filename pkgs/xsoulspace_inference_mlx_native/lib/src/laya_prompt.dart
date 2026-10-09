import 'dart:convert';
import 'dart:math' as math;

import 'laya_bytelevel_tokenizer.dart';
import 'laya_decision_server.dart';

/// One prepared model row: token ids, the per-option [MASK] marker
/// positions, and the question type index (0 choice, 1 score, 2 noul).
final class LayaPromptRow {
  const LayaPromptRow({
    required this.ids,
    required this.markers,
    required this.qtype,
  });

  final List<int> ids;
  final List<int> markers;
  final int qtype;
}

/// A typed question as the model sees it — the full choice/score/noul
/// surface. The harness wire serves choice questions; score and noul ride
/// the same model through this typed path (validation, benchmarks, and any
/// future wire version).
final class LayaTypedQuestion {
  const LayaTypedQuestion.choice(this.instructions, this.criteria)
    : type = 'choice',
      scoreLevels = null;

  const LayaTypedQuestion.score(this.instructions, List<String> levels)
    : type = 'score',
      criteria = null,
      scoreLevels = levels;

  const LayaTypedQuestion.noul(this.instructions, [Map<String, String>? crit])
    : type = 'noul',
      criteria = crit,
      scoreLevels = null;

  final String type;

  /// String instructions or pre-rendered structured JSON (the caller
  /// renders structured instructions with [renderLayaJson]).
  final String instructions;

  /// choice: label -> rendered criterion ('' = no description).
  final Map<String, String>? criteria;

  /// score: ordinal level texts.
  final List<String>? scoreLevels;

  /// noul: 'false'/'true' -> rendered criterion ('' = default phrasing).
  Map<String, String>? get noulCriteria => criteria;
}

/// Renders one criterion/instruction value as text — the reference's
/// `render_criterion`: strings pass through; anything structured becomes
/// `json.dumps(..., ensure_ascii=False, separators=(', ', ': '))`.
String renderLayaCriterion(final Object? value) {
  if (value is String) return value;
  return renderLayaJson(value);
}

/// Python `json.dumps(value, ensure_ascii=False)` (its DEFAULT separators —
/// `', '` and `': '`), which the reference uses for structured instructions
/// and state serialization. Dart's jsonEncode is compact, so the spaced
/// form is rendered here — tokenization depends on those spaces.
String renderLayaJson(final Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) {
    if (value is int) return '$value';
    return _pythonDouble(value.toDouble());
  }
  if (value is String) return '"${_jsonEscape(value)}"';
  if (value is List) return '[${value.map(renderLayaJson).join(', ')}]';
  if (value is Map) {
    return '{${value.entries.map((final e) =>
        '${renderLayaJson('${e.key}')}: ${renderLayaJson(e.value)}').join(', ')}}';
  }
  return renderLayaJson('$value');
}

String _pythonDouble(final double value) {
  // Python repr: 1.5 -> '1.5'; integral floats keep a trailing '.0'.
  if (value == value.truncateToDouble() && value.abs() < 1e16) {
    return '${value.truncate()}.0';
  }
  return '$value';
}

String _jsonEscape(final String text) =>
    jsonEncode(text).substring(1, jsonEncode(text).length - 1);

/// `render_options` — the option texts in label-index order. Noul is always
/// [false, true] so p[1] is the affirmative probability.
List<String> renderTypedOptions(final LayaTypedQuestion question) {
  switch (question.type) {
    case 'choice':
      return [
        for (final entry in question.criteria!.entries)
          entry.value.isEmpty
              ? entry.key
              : '${entry.key}: ${entry.value}',
      ];
    case 'score':
      return [
        for (var i = 0; i < question.scoreLevels!.length; i++)
          'level $i: ${question.scoreLevels![i]}',
      ];
    case 'noul':
      final crit = question.criteria ?? const {};
      final falseCrit = crit['false'] ?? '';
      final trueCrit = crit['true'] ?? '';
      return [
        'false: ${falseCrit.isEmpty ? 'no, the statement does not hold' : falseCrit}',
        'true: ${trueCrit.isEmpty ? 'yes, the statement holds' : trueCrit}',
      ];
  }
  throw StateError('unknown question type ${question.type}');
}

/// Ports `laya_mlx/common.py` build_sequence:
/// `[CLS] <type> <instructions> [SEP] [MASK] opt0 ... [SEP] state [SEP]`,
/// options capped at 48 tokens, the question head budgeted to [headMaxLen],
/// and the state filling the remaining [maxLen] budget (truncated on the
/// left only for list states).
LayaPromptRow buildTypedSequence({
  required LayaByteLevelTokenizer tokenizer,
  required String state,
  required LayaTypedQuestion question,
  int maxLen = 512,
  int headMaxLen = 192,
  bool truncateLeft = false,
}) {
  final optionTexts = renderTypedOptions(question);
  List<List<int>> buildOptions(final int cap) => [
    for (final text in optionTexts)
      [
        tokenizer.maskTokenId,
        ...tokenizer
            .encode(' $text'.replaceAll(tokenizer.maskLabel, ' '))
            .take(cap),
      ],
  ];

  var optionIds = buildOptions(48);
  var budget =
      headMaxLen - optionIds.fold(0, (total, ids) => total + ids.length);
  if (budget < 16) {
    // Too many or too long options: shrink every option evenly.
    final per = math.max(4, (headMaxLen - 16) ~/ math.max(1, optionIds.length));
    optionIds = buildOptions(per);
    budget = headMaxLen - optionIds.fold(0, (total, ids) => total + ids.length);
  }
  final headIds = tokenizer
      .encode(
        '${question.type} question: '
        '${question.instructions.replaceAll(tokenizer.maskLabel, ' ')}',
      )
      .take(math.max(8, budget).toInt())
      .toList();
  final ids = <int>[tokenizer.clsTokenId, ...headIds, tokenizer.sepTokenId];
  final markers = <int>[];
  for (final option in optionIds) {
    markers.add(ids.length);
    ids.addAll(option);
  }
  ids.add(tokenizer.sepTokenId);
  final room = math.max(0, maxLen - ids.length - 1);
  final stateTokens = tokenizer.encode(state.replaceAll(tokenizer.maskLabel, ' '));
  final kept = truncateLeft
      ? (stateTokens.length > room
            ? stateTokens.sublist(stateTokens.length - room)
            : stateTokens)
      : stateTokens.take(room).toList();
  final full = [...ids, ...kept, tokenizer.sepTokenId];
  return LayaPromptRow(
    ids: full.length > maxLen ? full.sublist(0, maxLen) : full,
    markers: [
      for (final m in markers)
        if (m < maxLen) m,
    ],
    qtype: const {'choice': 0, 'score': 1, 'noul': 2}[question.type] ?? 0,
  );
}

/// The wire's choice-question adapter over [buildTypedSequence].
LayaPromptRow buildChoiceSequence({
  required LayaByteLevelTokenizer tokenizer,
  required String state,
  required LayaDecisionQuestion question,
  int maxLen = 512,
  int headMaxLen = 192,
}) => buildTypedSequence(
  tokenizer: tokenizer,
  state: state,
  question: LayaTypedQuestion.choice(
    question.instructions,
    {
      for (final entry in question.criteria.entries)
        entry.key: renderLayaCriterion(entry.value),
    },
  ),
  maxLen: maxLen,
  headMaxLen: headMaxLen,
);

/// Temperature calibration — the checkpoint's fitted per-bucket scales, with
/// the laya-mlx honesty clamp: a fitted temperature below [tempMin] sharpens
/// the distribution (the shipped `choice:11+` bucket would multiply logits
/// ~10x and publish a coin flip as certainty), so it is confined to
/// [tempMin, tempMax].
const double tempMin = 0.5;
const double tempMax = 5.0;

double clampTemperature(final double value) {
  if (value.isNaN || value.isInfinite || value <= 0) return 1.0;
  return value.clamp(tempMin, tempMax);
}

/// `<type>:<size>` bucket key: 2 / 3-5 / 6-10 / 11+.
String tempBucketKey(final int qtype, final int optionCount) {
  final name = const {0: 'choice', 1: 'score', 2: 'noul'}[qtype] ?? 'choice';
  final size = optionCount <= 2
      ? '2'
      : optionCount <= 5
      ? '3-5'
      : optionCount <= 10
      ? '6-10'
      : '11+';
  return '$name:$size';
}

/// Normalized entropy confidence: `1 - H(p) / log(k)` over the first [k]
/// probabilities.
double confidenceFromProbs(final List<double> probs, final int k) {
  if (k < 2) return 1.0;
  var entropy = 0.0;
  for (var i = 0; i < k && i < probs.length; i++) {
    final p = probs[i];
    entropy -= p * math.log(p < 1e-12 ? 1e-12 : p);
  }
  return (1 - entropy / math.log(k.toDouble())).clamp(0.0, 1.0);
}
