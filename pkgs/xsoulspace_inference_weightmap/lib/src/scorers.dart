/// Eval scorers for the weightmap validation program.
///
/// FROZEN-ORACLE LAW (PREREG-A A4): once the A4 freeze lands, this file is a
/// frozen artifact keyed by sha256 in VERDICTS.md — changing it requires a new
/// prereg row, not an edit (see AGENTS.md).
///
/// DESIGN LAW — format invariance is the false-positive guard. The paper's
/// suites (MATH-500/GSM8K/IFEval) appear ONLY in P-arms as comparability;
/// certification cells must be scored so that an edit which merely changes
/// output FORMAT cannot score as a win. This repo has paid for format-artifact
/// false positives before. [formatInvariantScore] is that guard: it takes the
/// MINIMUM of a scorer over surface perturbations of the output, so a "win"
/// that depends on fences, trailing whitespace or blank-line decoration dies
/// on the perturbation that removes the decoration.
///
/// Pure Dart: no package dependencies (dart: libraries only).
library;

import 'dart:convert';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Answer extraction
// ---------------------------------------------------------------------------

final RegExp _boxedStart = RegExp(r'\\boxed\s*\{');

/// A token that looks numeric: optional sign, thousands-comma groups or a
/// plain integer/decimal or a simple fraction `a/b`, optional trailing `%`.
final RegExp _numericToken = RegExp(
  r'^[+-]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\d+(?:\.\d+)?/\d+(?:\.\d+)?)%?$',
);

/// Leading/trailing decoration that may be stripped from a whitespace token
/// before the numeric check (sentence punctuation, quotes, brackets,
/// currency). Interior characters (`.`, `,`, `/`, `%`) are never touched.
final RegExp _tokenDecoration = RegExp('''^["'(<\\[\$€£]+|["')>\\].,;:!?]+\$''');

/// Extracts the final answer from a model output.
///
/// Rule (documented for the frozen scorers [mathScore]/[gsm8kScore]):
/// 1. the LAST balanced `\boxed{...}` group, if any (final-answer convention);
/// 2. else the LAST whitespace token that looks numeric after edge decoration
///    is stripped (integer, decimal, thousands-comma, percent, simple
///    fraction);
/// 3. else `null` — callers score `null` as 0 and never crash.
String? extractFinalAnswer(String output) {
  final boxed = _lastBoxed(output);
  if (boxed != null && boxed.trim().isNotEmpty) return boxed.trim();
  final tokens = output.split(RegExp(r'\s+'));
  for (var i = tokens.length - 1; i >= 0; i--) {
    final cleaned = tokens[i].replaceAll(_tokenDecoration, '');
    if (cleaned.isNotEmpty && _numericToken.hasMatch(cleaned)) return cleaned;
  }
  return null;
}

/// Content of the last balanced `\boxed{...}` in [text], or `null` when no
/// balanced boxed group exists (an unbalanced one is skipped, not crashed on).
String? _lastBoxed(String text) {
  String? result;
  for (final match in _boxedStart.allMatches(text)) {
    final start = match.end; // just after the opening brace
    var depth = 1;
    var i = start;
    while (i < text.length) {
      final c = text[i];
      if (c == r'\') {
        i += 2; // escaped character (e.g. `\{`) cannot close the group
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          result = text.substring(start, i);
          break;
        }
      }
      i++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Numeric equivalence
// ---------------------------------------------------------------------------

final RegExp _thousandsComma = RegExp(r'^[+-]?\d{1,3}(?:,\d{3})+(?:\.\d+)?$');
final RegExp _plainFraction =
    RegExp(r'^\(?([+-]?\d+(?:\.\d+)?)\)?/\(?([+-]?\d+(?:\.\d+)?)\)?$');
final RegExp _latexFrac = RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}');
final RegExp _latexSqrt = RegExp(r'\\sqrt\{([^{}]*)\}');

/// Numeric equivalence of two answer strings with normalization.
///
/// Normalization handles: `$`/`\(`...`\)` math delimiters, LaTeX spacing
/// macros, `\left`/`\right`, `\dfrac`/`\tfrac`, `\frac{a}{b}` and plain
/// `a/b` fractions, thousands commas (`1,234`), trailing percent signs
/// (`50\%` == `50`, the MATH-suite convention), surrounding parens, case and
/// whitespace. When both sides parse as finite numbers they are compared with
/// a relative tolerance of 1e-6.
///
/// Simple sqrt/pi forms and other non-numeric strings fall back to a
/// normalized string comparison (`\sqrt{2}` == `sqrt(2)`, `2\pi` == `2pi`,
/// `\text{yes}` == `yes`). An empty side is never equivalent.
bool mathEquivalent(String pred, String gold) {
  final p = _normalizeMath(pred);
  final g = _normalizeMath(gold);
  if (p.isEmpty || g.isEmpty) return false;
  final pv = _numericValue(p);
  final gv = _numericValue(g);
  if (pv != null && gv != null && pv.isFinite && gv.isFinite) {
    final tolerance = 1e-6 * math.max(1.0, gv.abs());
    return (pv - gv).abs() <= tolerance;
  }
  return p == g; // string fallback (sqrt/pi forms, symbolic answers)
}

String _normalizeMath(String input) {
  var t = input.trim();
  t = t.replaceAll(RegExp(r'^\$+'), '').replaceAll(RegExp(r'\$+$'), '').trim();
  for (final macro in [
    r'\!', r'\,', r'\;', r'\:', r'\quad', r'\qquad', '~',
    r'\left', r'\right', r'\displaystyle',
  ]) {
    t = t.replaceAll(macro, '');
  }
  t = t.replaceAll(r'\dfrac', r'\frac').replaceAll(r'\tfrac', r'\frac');
  while (_latexFrac.hasMatch(t)) {
    t = t.replaceFirstMapped(_latexFrac, (m) => '(${m[1]})/(${m[2]})');
  }
  while (_latexSqrt.hasMatch(t)) {
    t = t.replaceFirstMapped(_latexSqrt, (m) => 'sqrt(${m[1]})');
  }
  t = t.replaceAll(r'\pi', 'pi');
  for (final cmd in [r'\text', r'\mathrm', r'\mathbf', r'\mathit', r'\operatorname']) {
    t = t.replaceAll(cmd, '');
  }
  t = t.replaceAll(r'\%', '%');
  t = t.replaceAll('{', '').replaceAll('}', '').replaceAll(r'\', '');
  t = t.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (t.endsWith('%')) t = t.substring(0, t.length - 1);
  return t;
}

/// Parses a normalized math string as a finite-or-not double, handling
/// thousands commas, simple fractions and one layer of surrounding parens.
/// Returns `null` when the string is not numeric.
double? _numericValue(String normalized) {
  var s = normalized;
  if (_thousandsComma.hasMatch(s)) s = s.replaceAll(',', '');
  final frac = _plainFraction.firstMatch(s);
  if (frac != null) {
    final numerator = double.tryParse(frac.group(1)!);
    final denominator = double.tryParse(frac.group(2)!);
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }
  if (s.startsWith('(') && s.endsWith(')')) {
    final inner = s.substring(1, s.length - 1);
    if (_parensBalanced(inner)) s = inner;
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  if (s.startsWith('+')) s = s.substring(1);
  return double.tryParse(s);
}

bool _parensBalanced(String s) {
  var depth = 0;
  for (final c in s.codeUnits) {
    if (c == 0x28) depth++; // '('
    if (c == 0x29) depth--; // ')'
    if (depth < 0) return false;
  }
  return depth == 0;
}

// ---------------------------------------------------------------------------
// Suite scorers (0/1 wrappers; extraction rule documented on each)
// ---------------------------------------------------------------------------

/// MATH-style 0/1 score.
///
/// Extraction rule: [extractFinalAnswer] — last balanced `\boxed{...}` first,
/// else last numeric-looking token, else `null`. An output with no extractable
/// answer scores 0 and never crashes. Equivalence is [mathEquivalent].
int mathScore(String output, String gold) {
  final answer = extractFinalAnswer(output);
  if (answer == null) return 0;
  return mathEquivalent(answer, gold) ? 1 : 0;
}

/// GSM8K-style 0/1 score.
///
/// Gold answers are plain final numbers (integers or decimals, possibly with
/// thousands commas). Same extraction rule as [mathScore]: boxed group first,
/// else last numeric-looking token, else `null` -> 0. Never crashes.
int gsm8kScore(String output, String gold) {
  final answer = extractFinalAnswer(output);
  if (answer == null) return 0;
  return mathEquivalent(answer, gold) ? 1 : 0;
}

// ---------------------------------------------------------------------------
// IFEval-style verifiable instruction checks
// ---------------------------------------------------------------------------

/// One failed instruction check. [check] is the spec's [IfevalSpec.checkName];
/// [detail] is the named one-line reason the check failed (never silent).
typedef IfevalFailure = ({String check, String detail});

/// A verifiable instruction spec: a pure predicate over the model output.
///
/// Sealed on purpose — the check vocabulary is closed and frozen with the
/// scorer (PREREG-A A4); adding a check is a new prereg row.
sealed class IfevalSpec {
  const IfevalSpec();

  /// Stable machine-readable check name; appears in [IfevalFailure.check].
  String get checkName;

  /// `null` when [output] satisfies the instruction; otherwise a named
  /// one-line failure reason.
  String? checkReason(String output);

  /// Pure predicate: does [output] satisfy the instruction?
  bool check(String output) => checkReason(output) == null;
}

/// Word-count bounds over whitespace-split tokens of the trimmed output.
/// At least one bound is required (named refusal otherwise).
final class WordCountBound extends IfevalSpec {
  WordCountBound({this.minWords, this.maxWords}) {
    if (minWords == null && maxWords == null) {
      throw ArgumentError(
        'WORD_COUNT_BOUND_EMPTY: at least one of minWords/maxWords is required',
      );
    }
    if ((minWords ?? 0) < 0 || (maxWords ?? 0) < 0) {
      throw ArgumentError(
        'WORD_COUNT_BOUND_NEGATIVE: bounds must be >= 0 (min=$minWords, max=$maxWords)',
      );
    }
    if (minWords != null && maxWords != null && minWords! > maxWords!) {
      throw ArgumentError(
        'WORD_COUNT_BOUND_INVERTED: min=$minWords > max=$maxWords',
      );
    }
  }

  final int? minWords;
  final int? maxWords;

  @override
  String get checkName => 'word_count_bound';

  @override
  String? checkReason(String output) {
    final n = wordCount(output);
    if (minWords != null && n < minWords!) {
      return '$checkName: $n words < min $minWords';
    }
    if (maxWords != null && n > maxWords!) {
      return '$checkName: $n words > max $maxWords';
    }
    return null;
  }
}

/// Word count: whitespace-split tokens of the trimmed output (empty -> 0).
int wordCount(String output) {
  final trimmed = output.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// Every keyword must appear (case-insensitive substring match).
final class KeywordInclude extends IfevalSpec {
  KeywordInclude(this.keywords) {
    if (keywords.isEmpty) {
      throw ArgumentError('KEYWORDS_EMPTY: keyword list must not be empty');
    }
  }

  final List<String> keywords;

  @override
  String get checkName => 'keyword_include';

  @override
  String? checkReason(String output) {
    final lower = output.toLowerCase();
    final missing =
        keywords.where((k) => !lower.contains(k.toLowerCase())).toList();
    if (missing.isEmpty) return null;
    return '$checkName: missing ${missing.join(", ")}';
  }
}

/// No keyword may appear (case-insensitive substring match).
final class KeywordExclude extends IfevalSpec {
  KeywordExclude(this.keywords) {
    if (keywords.isEmpty) {
      throw ArgumentError('KEYWORDS_EMPTY: keyword list must not be empty');
    }
  }

  final List<String> keywords;

  @override
  String get checkName => 'keyword_exclude';

  @override
  String? checkReason(String output) {
    final lower = output.toLowerCase();
    final present =
        keywords.where((k) => lower.contains(k.toLowerCase())).toList();
    if (present.isEmpty) return null;
    return '$checkName: forbidden keywords present ${present.join(", ")}';
  }
}

/// The whole trimmed output must parse as one JSON value (dart:convert).
final class JsonOnlyOutput extends IfevalSpec {
  const JsonOnlyOutput();

  @override
  String get checkName => 'json_only';

  @override
  String? checkReason(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return '$checkName: output is empty';
    try {
      jsonDecode(trimmed);
      return null;
    } on FormatException catch (e) {
      return '$checkName: not parseable as JSON (${e.message})';
    }
  }
}

/// Every non-empty line must be a bullet or numbered list item
/// (`-`, `*`, `•`, `1.`, `1)`), with at least [minItems] items.
final class BulletListFormat extends IfevalSpec {
  BulletListFormat({this.minItems = 1}) {
    if (minItems < 1) {
      throw ArgumentError(
        'BULLET_MIN_ITEMS_INVALID: minItems must be >= 1 (got $minItems)',
      );
    }
  }

  static final RegExp _bulletLine =
      RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+\S');

  final int minItems;

  @override
  String get checkName => 'bullet_list';

  @override
  String? checkReason(String output) {
    final lines = output
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final offenders =
        lines.where((l) => !_bulletLine.hasMatch(l)).toList(growable: false);
    if (offenders.isNotEmpty) {
      return '$checkName: ${offenders.length} non-empty line(s) are not list items';
    }
    if (lines.length < minItems) {
      return '$checkName: ${lines.length} items < min $minItems';
    }
    return null;
  }
}

/// The raw output must start with [prefix] (exact, case-sensitive, no trim —
/// IFEval convention).
final class StartsWithPrefix extends IfevalSpec {
  StartsWithPrefix(this.prefix) {
    if (prefix.isEmpty) {
      throw ArgumentError('PREFIX_EMPTY: prefix must not be empty');
    }
  }

  final String prefix;

  @override
  String get checkName => 'starts_with';

  @override
  String? checkReason(String output) {
    if (output.startsWith(prefix)) return null;
    return '$checkName: output does not start with "$prefix"';
  }
}

/// The first non-empty line (the title line) must contain at least one letter
/// and every letter on it must be uppercase. Digits and punctuation are
/// allowed; an output with no non-empty line or no letters fails.
final class UppercaseTitleLine extends IfevalSpec {
  const UppercaseTitleLine();

  @override
  String get checkName => 'uppercase_title_line';

  @override
  String? checkReason(String output) {
    String? title;
    for (final line in output.split('\n')) {
      if (line.trim().isNotEmpty) {
        title = line.trim();
        break;
      }
    }
    if (title == null) return '$checkName: output has no non-empty line';
    final hasLetters = title.toUpperCase() != title.toLowerCase();
    if (!hasLetters) return '$checkName: title line has no letters';
    if (title.toUpperCase() != title) {
      return '$checkName: title line is not ALL UPPERCASE';
    }
    return null;
  }
}

/// Runs every spec against [output] and returns the failures (empty = pass).
/// Failures carry the check name and a named reason — refusals are never
/// silent.
List<IfevalFailure> ifevalChecks(
  Iterable<IfevalSpec> specs,
  String output,
) {
  final failures = <IfevalFailure>[];
  for (final spec in specs) {
    final reason = spec.checkReason(output);
    if (reason != null) {
      failures.add((check: spec.checkName, detail: reason));
    }
  }
  return failures;
}

/// IFEval-style 0/1 score: 1 iff every spec passes (empty spec list = 1).
int ifevalScore(Iterable<IfevalSpec> specs, String output) =>
    ifevalChecks(specs, output).isEmpty ? 1 : 0;

// ---------------------------------------------------------------------------
// Token-limit rate
// ---------------------------------------------------------------------------

/// Fraction of outputs that hit the token cap (`count >= cap`): the
/// token-limit-hit rate the paper reports (base ~93%, edited ~31-33%).
///
/// Named refusals, never silent zeros:
/// - `NONPOSITIVE_CAP` when [cap] <= 0;
/// - `EMPTY_TOKEN_SAMPLE` when [outputTokenCounts] is empty (a rate with no
///   denominator is undefined, not 0);
/// - `NEGATIVE_TOKEN_COUNT` on corrupt data.
double tokenLimitRate(List<int> outputTokenCounts, int cap) {
  if (cap <= 0) {
    throw ArgumentError.value(cap, 'cap', 'NONPOSITIVE_CAP: cap must be > 0');
  }
  if (outputTokenCounts.isEmpty) {
    throw ArgumentError(
      'EMPTY_TOKEN_SAMPLE: token-limit rate is undefined on an empty sample',
    );
  }
  for (final c in outputTokenCounts) {
    if (c < 0) {
      throw ArgumentError.value(
        c,
        'outputTokenCounts',
        'NEGATIVE_TOKEN_COUNT: token counts must be >= 0',
      );
    }
  }
  final hits = outputTokenCounts.where((c) => c >= cap).length;
  return hits / outputTokenCounts.length;
}

// ---------------------------------------------------------------------------
// Format-invariance guard
// ---------------------------------------------------------------------------

/// One surface perturbation of an output, named so failures can quote which
/// perturbation broke a "win".
typedef SurfacePerturbation = ({String name, String output});

/// The four surface perturbations the guard applies (to the ORIGINAL output,
/// not chained): identity, trailing-whitespace trim, one markdown fence pair
/// stripped, blank lines collapsed.
List<SurfacePerturbation> surfacePerturbations(String output) =>
    <SurfacePerturbation>[
      (name: 'identity', output: output),
      (name: 'trim_trailing_whitespace', output: output.trimRight()),
      (name: 'strip_one_fence_pair', output: stripOneFencePair(output)),
      (name: 'collapse_blank_lines', output: collapseBlankLines(output)),
    ];

/// Strips at most ONE markdown fence pair wrapping the whole (trimmed)
/// output; a non-fenced output is returned unchanged. Fences are line-based:
/// an opening ```` ``` ```` line and a closing ```` ``` ```` at the very end.
String stripOneFencePair(String output) {
  final trimmed = output.trim();
  final match =
      RegExp('^```[^\\n]*\\n([\\s\\S]*?)\\n?```\$').firstMatch(trimmed);
  return match == null ? output : match.group(1)!;
}

/// Collapses runs of blank lines: two or more newline-terminated lines
/// (whitespace-only allowed between) become a single newline.
String collapseBlankLines(String output) =>
    output.replaceAll(RegExp(r'(?:[ \t]*\n){2,}[ \t]*'), '\n');

/// FORMAT-INVARIANCE GUARD: the minimum of [score] over the surface
/// perturbations of [output] (see [surfacePerturbations]).
///
/// Invariance is the guard: a certified cell must keep its score under
/// surface-only changes, so a format-only "win" must NOT survive this min —
/// a scorer that only rewards fenced (or padded, or blank-line-decorated)
/// output drops to its perturbed value here and the win dies. Real ability
/// changes are format-stable and pass through unchanged.
double formatInvariantScore(double Function(String) score, String output) =>
    surfacePerturbations(output)
        .map((p) => score(p.output))
        .reduce(math.min);

// ---------------------------------------------------------------------------
// Length normalization
// ---------------------------------------------------------------------------

/// Correct cells per generated token: `correctCells / totalTokens`.
///
/// Prevents long-output inflation: plain accuracy cannot distinguish two
/// configs with equal correct counts where one burned 10x the tokens, and a
/// verbose wrong answer earns nothing while paying its full token cost. The
/// length-normalized score always ranks the shorter correct run above the
/// longer one, and any long wrong run below it.
///
/// Named refusals: `NEGATIVE_CORRECT_CELLS` when [correctCells] < 0;
/// `NONPOSITIVE_TOKEN_TOTAL` when [totalTokens] <= 0 (an undefined rate is a
/// refusal, not a silent zero).
double lengthNormalized(int correctCells, int totalTokens) {
  if (correctCells < 0) {
    throw ArgumentError.value(
      correctCells,
      'correctCells',
      'NEGATIVE_CORRECT_CELLS: correct-cell count must be >= 0',
    );
  }
  if (totalTokens <= 0) {
    throw ArgumentError.value(
      totalTokens,
      'totalTokens',
      'NONPOSITIVE_TOKEN_TOTAL: token total must be > 0',
    );
  }
  return correctCells / totalTokens;
}
