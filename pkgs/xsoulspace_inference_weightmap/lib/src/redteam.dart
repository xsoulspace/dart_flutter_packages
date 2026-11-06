/// V-4 red-team refusal bench (PREREG-C §V-4, scorer tier).
///
/// The bench plants N=12 fake wins as fixtures — 6 format artifacts,
/// 4 length tricks, 2 battery gamers — and runs the certification rule's
/// guards over each plant using ONLY the frozen oracles:
///
/// - [formatInvariantScore] / [surfacePerturbations] (frozen guard core: min
///   over identity, trim_trailing_whitespace, strip_one_fence_pair,
///   collapse_blank_lines), extended by two bench-NAMED case variants
///   (`lowercase_all`, `uppercase_all`) because PREREG-C names `label-case`
///   as a refused format subclass and the frozen four do not perturb case.
///   The frozen-core min is reported separately as `frozen_invariant` so the
///   coverage fact is recorded, not hidden;
/// - [lengthNormalized] against the pre-registered floor the fixture carries
///   (`length_norm_floor`), plus [tokenLimitRate] as the cap-hit signal;
/// - [ProbeBookkeeping.assertDisjoint] (probes.dart), which excludes
///   memorized-answer cells from certification evidence with a NAMED
///   [ProbeSetViolation] (`PROBE_OVERLAP` / `DUP_IN_SET`).
///
/// Verdict per plant: `REFUSED` with NAMED refusal reasons when any guard
/// fires; otherwise the NAMED leak of the plant's class
/// (`FORMAT_ARTIFACT_LEAK` / `LENGTH_TRICK_LEAK` / `MEMORIZATION_LEAK`).
/// The PREREG-C floor (12/12 named refusals) is FROZEN: [preregRefusalFloor]
/// is a constant, a fixture that tries to carry a different `refusal_floor`
/// is refused with `REFUSAL_FLOOR_MISMATCH`, and a bench below floor reports
/// the truth — plants are never tuned to pass.
///
/// The naive scorers registered here are NOT oracles. They are the bench's
/// stand-ins for format-sensitive scoring pipelines (the false positive this
/// repo has paid for): each gates a frozen content check ([mathScore] /
/// [mathEquivalent]) behind a surface-form requirement, and the count-based
/// ones never divide by length. The guard's job is to drive the min over
/// surface variants of such a scorer to zero.
///
/// Mutation-check surface: [RedTeamBench.run] / [RedTeamBench.evaluatePlant]
/// take per-guard bypass parameters so a test can prove each leak class MUST
/// leak when its guard is removed — the 12/12 floor is guard-caused, not
/// vacuous. Bypassing is bench-side instrumentation; the frozen sources are
/// never touched.
///
/// Pure Dart: dart: libraries plus frozen package sources only (no dart:io —
/// fixture/receipt I/O lives with the callers in test/ and tool/runs/).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'probes.dart';
import 'scorers.dart';

// ---------------------------------------------------------------------------
// Classes and verdict vocabulary
// ---------------------------------------------------------------------------

/// The three planted fake-win classes (PREREG-C V-4) and their NAMED leaks.
enum RedTeamClass {
  formatArtifact('FORMAT_ARTIFACT', 'FORMAT_ARTIFACT_LEAK'),
  lengthTrick('LENGTH_TRICK', 'LENGTH_TRICK_LEAK'),
  memorization('MEMORIZATION', 'MEMORIZATION_LEAK');

  const RedTeamClass(this.wire, this.leakVerdict);

  /// Fixture/receipt spelling of the class.
  final String wire;

  /// Verdict string when this class's plant is NOT refused: the leak is
  /// named after the guard that should have caught it.
  final String leakVerdict;

  /// Parses the wire spelling; an unknown class is a NAMED refusal
  /// (`UNKNOWN_CLASS=`), never a silent default.
  static RedTeamClass parseWire(String wire, [String ctx = '']) {
    for (final c in RedTeamClass.values) {
      if (c.wire == wire) return c;
    }
    throw FormatException(
      ctx.isEmpty ? 'UNKNOWN_CLASS=$wire' : 'UNKNOWN_CLASS=$wire (plant $ctx)',
    );
  }
}

/// The refused verdict string. A non-REFUSED verdict is always the class's
/// NAMED leak ([RedTeamClass.leakVerdict]).
const String verdictRefused = 'REFUSED';

// ---------------------------------------------------------------------------
// Naive-scorer registry (bench-side plants, NOT oracles)
// ---------------------------------------------------------------------------

/// Naive scorers gated on surface form: each requires a decoration (fence,
/// trailing pad, exact-case label) on top of a frozen content check. A
/// FORMAT_ARTIFACT plant must use one of these.
const Set<String> formatGatedNaiveScorers = {
  'requires_opening_fence',
  'requires_full_fence_wrap',
  'requires_trailing_newline',
  'requires_blank_line_pad',
  'requires_uppercase_label',
  'requires_titlecase_label',
};

/// Naive scorers that count raw correct cells and never divide by length. A
/// LENGTH_TRICK plant must use one of these. `gold_occurrence_count` counts
/// word-boundary occurrences of the gold string in the output (the
/// repetition-inflation pathology); `raw_cell_count_ignores_length` trusts
/// the fixture's raw count (the verbose-inflation pathology).
const Set<String> countBasedNaiveScorers = {
  'raw_cell_count_ignores_length',
  'gold_occurrence_count',
};

/// Plain frozen content scorer (no format gate): the only naive scorer a
/// MEMORIZATION plant may use — the battery gamer's win is content-real and
/// format-stable; only probe bookkeeping can catch it.
const Set<String> contentNaiveScorers = {'math_score_gold'};

/// Every scorer name the bench knows. An unknown name is a NAMED refusal
/// (`UNKNOWN_NAIVE_SCORER=`), never a silent default.
const Set<String> knownNaiveScorers = {
  ...formatGatedNaiveScorers,
  ...countBasedNaiveScorers,
  ...contentNaiveScorers,
};

double _labelScore(String output, String gold, RegExp label) {
  final m = label.firstMatch(output);
  if (m == null) return 0.0;
  return mathEquivalent(m.group(1)!, gold) ? 1.0 : 0.0;
}

/// The surface-consuming naive scorers: `(output, gold) -> 0.0|1.0`. Content
/// checks are the frozen [mathScore]/[mathEquivalent]; only the gates are
/// bench-side.
final Map<String, double Function(String output, String gold)>
    _surfaceNaiveScorers = {
  'requires_opening_fence': (o, g) => o.trimLeft().startsWith('```')
      ? mathScore(o, g).toDouble()
      : 0.0,
  'requires_full_fence_wrap': (o, g) {
    final t = o.trim();
    return t.startsWith('```') && t.endsWith('```')
        ? mathScore(o, g).toDouble()
        : 0.0;
  },
  'requires_trailing_newline': (o, g) =>
      o.endsWith('\n') ? mathScore(o, g).toDouble() : 0.0,
  'requires_blank_line_pad': (o, g) => o.length - o.trimRight().length >= 2
      ? mathScore(o, g).toDouble()
      : 0.0,
  'requires_uppercase_label': (o, g) =>
      _labelScore(o, g, RegExp(r'FINAL ANSWER:\s*(\S+)')),
  'requires_titlecase_label': (o, g) =>
      _labelScore(o, g, RegExp(r'Answer:\s*(\S+)')),
  'math_score_gold': (o, g) => mathScore(o, g).toDouble(),
};

/// Word-boundary occurrences of [gold] in [output] (the repetition-inflation
/// count). Word boundaries keep `18` from matching inside `118`.
int countWordBoundaryOccurrences(String output, String gold) =>
    RegExp('\\b${RegExp.escape(gold)}\\b').allMatches(output).length;

// ---------------------------------------------------------------------------
// Perturbation set: frozen core UNION named case variants
// ---------------------------------------------------------------------------

/// The two bench-NAMED case variants. PREREG-C §V-4 names `label-case` as a
/// refused format subclass; the frozen [surfacePerturbations] do not perturb
/// case, so the bench extends the min with these two — named, recorded per
/// plant (the `killer` field), and reported alongside the frozen-core min.
List<SurfacePerturbation> casePerturbations(String output) =>
    <SurfacePerturbation>[
      (name: 'lowercase_all', output: output.toLowerCase()),
      (name: 'uppercase_all', output: output.toUpperCase()),
    ];

/// The full bench perturbation set: the frozen four first (in frozen order),
/// then the two named case variants.
List<SurfacePerturbation> redteamPerturbations(String output) =>
    <SurfacePerturbation>[
      ...surfacePerturbations(output),
      ...casePerturbations(output),
    ];

/// The bench invariant score: the frozen [formatInvariantScore] min over the
/// frozen perturbations, further minimized over the named case variants.
/// Composition, not reimplementation: the frozen guard is the core.
double redteamInvariantScore(double Function(String) score, String output) {
  final frozen = formatInvariantScore(score, output);
  return casePerturbations(output)
      .map((p) => score(p.output))
      .fold<double>(frozen, math.min);
}

/// The NAMED first perturbation that scores below [naiveScore] — the
/// perturbation that broke the planted "win" (null when none does).
String? firstWinBreakingPerturbation(
  double Function(String) score,
  String output,
  double naiveScore,
) {
  for (final p in redteamPerturbations(output)) {
    if (score(p.output) < naiveScore) return p.name;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Fixture parsing helpers (NAMED FormatExceptions, receipts.dart convention)
// ---------------------------------------------------------------------------

String _reqString(Map<String, Object?> json, String field, String ctx) {
  final v = json[field];
  if (v == null) throw FormatException('MISSING_FIELD=$field (plant $ctx)');
  if (v is! String) {
    throw FormatException(
      'MALFORMED_FIELD=$field expected=String found=${v.runtimeType} '
      '(plant $ctx)',
    );
  }
  return v;
}

String? _optString(Map<String, Object?> json, String field, String ctx) {
  final v = json[field];
  if (v == null) return null;
  if (v is! String) {
    throw FormatException(
      'MALFORMED_FIELD=$field expected=String found=${v.runtimeType} '
      '(plant $ctx)',
    );
  }
  return v;
}

int _reqInt(Map<String, Object?> json, String field, String ctx) {
  final v = json[field];
  if (v == null) throw FormatException('MISSING_FIELD=$field (plant $ctx)');
  if (v is! int) {
    throw FormatException(
      'MALFORMED_FIELD=$field expected=int found=${v.runtimeType} (plant $ctx)',
    );
  }
  return v;
}

int? _optInt(Map<String, Object?> json, String field, String ctx) {
  final v = json[field];
  if (v == null) return null;
  if (v is! int) {
    throw FormatException(
      'MALFORMED_FIELD=$field expected=int found=${v.runtimeType} (plant $ctx)',
    );
  }
  return v;
}

ProbeSet _reqProbeSet(Map<String, Object?> json, String ctx) {
  final raw = json['probe_sets'];
  if (raw == null) {
    throw FormatException('MISSING_FIELD=probe_sets (plant $ctx)');
  }
  if (raw is! Map) {
    throw FormatException(
      'MALFORMED_FIELD=probe_sets expected=object found=${raw.runtimeType} '
      '(plant $ctx)',
    );
  }
  List<String> list(String name) {
    final v = raw[name];
    if (v == null) {
      throw FormatException('MISSING_FIELD=probe_sets.$name (plant $ctx)');
    }
    if (v is! List || v.any((e) => e is! String)) {
      throw FormatException(
        'MALFORMED_FIELD=probe_sets.$name expected=List<String> (plant $ctx)',
      );
    }
    return v.cast<String>();
  }

  return ProbeSet(
    localization: list('localization'),
    certification: list('certification'),
    generalization: list('generalization'),
  );
}

// ---------------------------------------------------------------------------
// Plant
// ---------------------------------------------------------------------------

/// One planted fake win. Parsing refuses with NAMED [FormatException]s; see
/// the library doc for the code list.
final class RedTeamPlant {
  const RedTeamPlant({
    required this.id,
    required this.klass,
    required this.subclass,
    required this.naiveScorer,
    required this.gold,
    required this.output,
    required this.rawCorrectCells,
    required this.cellsRequired,
    required this.tokenCount,
    required this.tokenCap,
    this.cell,
    this.expectedAnswer,
    this.memorizationCue,
    this.probeSets,
  });

  /// Unique fixture id (e.g. `V4-FA-1`).
  final String id;

  /// The planted fake-win class.
  final RedTeamClass klass;

  /// Fixture subclass label (`fence_only`, `trailing_pad`, `label_case`,
  /// `verbose_single_cell`, `cap_hit_verbosity`, `repetition_inflation`,
  /// `padded_multicell`, `verbatim_cell_replay`). Informational; verdict
  /// logic keys on [klass].
  final String subclass;

  /// Registry name of the naive (format-sensitive / length-ignorant) scorer.
  final String naiveScorer;

  /// The cell's gold answer the frozen content checks score against.
  final String gold;

  /// The planted model output.
  final String output;

  /// Raw correct-cell count the length-ignorant metric claims (the frozen
  /// [lengthNormalized] numerator).
  final int rawCorrectCells;

  /// Cells the naive metric requires for a "win" (its denominator-free
  /// threshold).
  final int cellsRequired;

  /// Pipeline-recorded generated token count of the planted run (the frozen
  /// [lengthNormalized] denominator; fixture claim at scorer tier).
  final int tokenCount;

  /// Token cap for the frozen [tokenLimitRate] signal.
  final int tokenCap;

  /// MEMORIZATION plants: the frozen G-cell whose expected answer the output
  /// replays (a [CellRef] — probes.dart contract, strings only).
  final CellRef? cell;

  /// MEMORIZATION plants: the cell's expected answer string, reproduced
  /// verbatim in [output] (parse-checked: `MEMO_PLANT_NOT_VERBATIM`).
  final String? expectedAnswer;

  /// MEMORIZATION plants: the marked memorization cue (what was replayed and
  /// which probe-bookkeeping violation excludes the cell). Quoted verbatim
  /// in the refusal reason.
  final String? memorizationCue;

  /// MEMORIZATION plants: the three probe sets the frozen
  /// [ProbeBookkeeping.assertDisjoint] judges.
  final ProbeSet? probeSets;

  /// Parses one plant. [index] names the plant in errors before its id is
  /// known.
  factory RedTeamPlant.fromJson(Map<String, Object?> json, {required int index}) {
    final where = 'plants[$index]';
    final id = _reqString(json, 'id', where);
    final klass =
        RedTeamClass.parseWire(_reqString(json, 'class', id), id);
    final naiveScorer = _reqString(json, 'naive_scorer', id);
    if (!knownNaiveScorers.contains(naiveScorer)) {
      throw FormatException(
        'UNKNOWN_NAIVE_SCORER=$naiveScorer (plant $id)',
      );
    }
    final gold = _reqString(json, 'gold', id);
    final output = _reqString(json, 'output', id);
    final rawCorrectCells = _reqInt(json, 'raw_correct_cells', id);
    if (rawCorrectCells < 0) {
      throw FormatException(
        'MALFORMED_FIELD=raw_correct_cells must be >= 0 (plant $id)',
      );
    }
    final cellsRequired = _reqInt(json, 'cells_required', id);
    if (cellsRequired < 1) {
      throw FormatException(
        'MALFORMED_FIELD=cells_required must be >= 1 (plant $id)',
      );
    }
    final tokenCount = _reqInt(json, 'token_count', id);
    if (tokenCount <= 0) {
      throw FormatException(
        'MALFORMED_FIELD=token_count must be > 0 (plant $id)',
      );
    }
    final tokenCap =
        _optInt(json, 'token_cap', id) ?? RedTeamBench.defaultTokenCap;
    if (tokenCap <= 0) {
      throw FormatException(
        'MALFORMED_FIELD=token_cap must be > 0 (plant $id)',
      );
    }

    CellRef? cell;
    String? expectedAnswer;
    String? memorizationCue;
    ProbeSet? probeSets;
    switch (klass) {
      case RedTeamClass.formatArtifact:
        if (!formatGatedNaiveScorers.contains(naiveScorer)) {
          throw FormatException(
            'CLASS_SCORER_MISMATCH=$id: FORMAT_ARTIFACT plant must use a '
            'format-gated naive scorer (got $naiveScorer)',
          );
        }
      case RedTeamClass.lengthTrick:
        if (!countBasedNaiveScorers.contains(naiveScorer)) {
          throw FormatException(
            'CLASS_SCORER_MISMATCH=$id: LENGTH_TRICK plant must use a '
            'count-based naive scorer (got $naiveScorer)',
          );
        }
        if (naiveScorer == 'gold_occurrence_count') {
          final found = countWordBoundaryOccurrences(output, gold);
          if (found != rawCorrectCells) {
            throw FormatException(
              'FIXTURE_COUNT_MISMATCH=$id: gold "$gold" occurs $found '
              'time(s) (word-boundary) but raw_correct_cells claims '
              '$rawCorrectCells',
            );
          }
        }
      case RedTeamClass.memorization:
        if (!contentNaiveScorers.contains(naiveScorer)) {
          throw FormatException(
            'CLASS_SCORER_MISMATCH=$id: MEMORIZATION plant must use '
            'math_score_gold (got $naiveScorer) — the gamer\'s win is '
            'content-real; only bookkeeping may catch it',
          );
        }
        cell = CellRef(_reqString(json, 'cell', id));
        expectedAnswer = _reqString(json, 'expected_answer', id);
        memorizationCue = _reqString(json, 'memorization_cue', id);
        probeSets = _reqProbeSet(json, id);
        if (!output.contains(expectedAnswer)) {
          throw FormatException(
            'MEMO_PLANT_NOT_VERBATIM=$id: output does not reproduce '
            'expected_answer "$expectedAnswer" verbatim',
          );
        }
    }

    return RedTeamPlant(
      id: id,
      klass: klass,
      subclass: _optString(json, 'subclass', id) ?? '',
      naiveScorer: naiveScorer,
      gold: gold,
      output: output,
      rawCorrectCells: rawCorrectCells,
      cellsRequired: cellsRequired,
      tokenCount: tokenCount,
      tokenCap: tokenCap,
      cell: cell,
      expectedAnswer: expectedAnswer,
      memorizationCue: memorizationCue,
      probeSets: probeSets,
    );
  }
}

// ---------------------------------------------------------------------------
// Result and summary
// ---------------------------------------------------------------------------

/// One plant's bench result: the four pre-registered values
/// (`naive`, `invariant`, `length_norm`, `memo_flag`), the verdict, and the
/// NAMED refusal reasons / killer perturbation when refused.
final class PlantResult {
  const PlantResult({
    required this.plant,
    required this.naiveScore,
    required this.invariantScore,
    required this.frozenInvariantScore,
    required this.lengthNorm,
    required this.memoFlag,
    required this.capHitRate,
    required this.killerPerturbation,
    required this.refusalReasons,
    required this.certificationExcluded,
    required this.verdict,
  });

  final RedTeamPlant plant;

  /// Naive (format-sensitive / length-ignorant) score of the raw output.
  final double naiveScore;

  /// Bench invariant score: min over frozen perturbations UNION the named
  /// case variants. Drives the FORMAT guard condition.
  final double invariantScore;

  /// The frozen [formatInvariantScore] min alone (frozen four
  /// perturbations). Reported so the frozen guard's own coverage is visible.
  final double frozenInvariantScore;

  /// Frozen [lengthNormalized] of (rawCorrectCells, tokenCount).
  final double lengthNorm;

  /// True when the output replays the cell's expected answer verbatim AND
  /// the frozen probe bookkeeping refuses the plant's probe sets.
  final bool memoFlag;

  /// Frozen [tokenLimitRate] cap-hit signal for the single planted run.
  final double capHitRate;

  /// The NAMED perturbation that first scored below [naiveScore] (null when
  /// the win is surface-stable).
  final String? killerPerturbation;

  /// Every guard that fired, NAMED (`FORMAT_INVARIANT_MIN_ZERO`,
  /// `LENGTH_NORMALIZED_BELOW_FLOOR`, `MEMORIZATION_EXCLUDED`), in guard
  /// order. Empty iff the plant leaked.
  final List<String> refusalReasons;

  /// True when probe bookkeeping excluded this plant's cell from
  /// certification evidence.
  final bool certificationExcluded;

  /// `REFUSED` or the class's NAMED leak verdict.
  final String verdict;

  bool get refused => verdict == verdictRefused;

  /// The primary NAMED refusal (first guard that fired), or null on a leak.
  String? get refusal => refusalReasons.isEmpty ? null : refusalReasons.first;

  /// Receipt line: the pre-registered fields first
  /// (`id, class, naive, invariant, length_norm, memo_flag, verdict`), then
  /// the reporting extras.
  Map<String, Object?> toJson() => {
        'id': plant.id,
        'class': plant.klass.wire,
        'naive': naiveScore,
        'invariant': invariantScore,
        'length_norm': lengthNorm,
        'memo_flag': memoFlag,
        'verdict': verdict,
        'subclass': plant.subclass,
        'frozen_invariant': frozenInvariantScore,
        'cap_hit_rate': capHitRate,
        'killer': killerPerturbation,
        'refusal': refusal,
        'refusal_reasons': refusalReasons,
        'certification_excluded': certificationExcluded,
      };
}

/// Bench summary: `{refusals, leaks, floor_met}` plus the denominator
/// context a ledger row needs. `floor_met` is true ONLY at the frozen
/// PREREG-C floor: all [RedTeamBench.preregRefusalFloor] plants evaluated
/// and every one REFUSED.
final class RedTeamSummary {
  const RedTeamSummary({
    required this.plantsEvaluated,
    required this.refusals,
    required this.leaks,
    required this.floorMet,
    required this.preregFloor,
    required this.lengthNormFloor,
    required this.refusalsByClass,
    required this.leaksNamed,
    required this.excludedCells,
  });

  final int plantsEvaluated;
  final int refusals;
  final int leaks;
  final bool floorMet;
  final int preregFloor;
  final double lengthNormFloor;

  /// Refusals per class wire name (`FORMAT_ARTIFACT`, `LENGTH_TRICK`,
  /// `MEMORIZATION`), in enum order.
  final Map<String, int> refusalsByClass;

  /// NAMED leak verdicts (empty when the floor is met).
  final List<String> leaksNamed;

  /// Cell names probe bookkeeping excluded from certification evidence.
  final List<String> excludedCells;

  /// Receipt summary line. [date] is stamped by the runner (the bench itself
  /// is deterministic).
  Map<String, Object?> toJson({String? date}) => {
        'date': ?date,
        'arm': 'V-4',
        'tier': 'scorer',
        'refusals': refusals,
        'leaks': leaks,
        'floor_met': floorMet,
        'prereg_floor': preregFloor,
        'length_norm_floor': lengthNormFloor,
        'plants_evaluated': plantsEvaluated,
        'refusals_by_class': refusalsByClass,
        'leaks_named': leaksNamed,
        'memorized_cells_excluded': excludedCells,
      };
}

// ---------------------------------------------------------------------------
// Bench
// ---------------------------------------------------------------------------

/// The V-4 scorer-tier bench: parses the plants fixture, evaluates every
/// plant against the certification rule's guards (frozen scorers/probes
/// only), and summarizes against the FROZEN PREREG-C floor.
final class RedTeamBench {
  RedTeamBench._({required this.plants, required this.lengthNormFloor});

  /// The FROZEN PREREG-C V-4 scorer-tier floor: 12/12 named refusals. A
  /// fixture cannot edit it (`REFUSAL_FLOOR_MISMATCH`); below floor the
  /// summary tells the truth (`floor_met: false`).
  static const int preregRefusalFloor = 12;

  /// Default token cap for the frozen [tokenLimitRate] signal.
  static const int defaultTokenCap = 32768;

  /// The parsed plants, in fixture order.
  final List<RedTeamPlant> plants;

  /// The pre-registered length-normalized floor (correct cells per generated
  /// token) the fixture carries; a plant below it is refused.
  final double lengthNormFloor;

  /// Parses the fixture json. NAMED refusals (FormatException):
  /// `FIXTURE_NOT_JSON`, `FIXTURE_NOT_OBJECT`, `REFUSAL_FLOOR_MISMATCH`
  /// (the frozen floor cannot be edited via fixture),
  /// `MISSING_FIELD=length_norm_floor`, `LENGTH_NORM_FLOOR_INVALID`,
  /// `MISSING_FIELD=plants`, `MALFORMED_FIELD=plants`, `DUPLICATE_PLANT_ID`,
  /// plus every per-plant code (see [RedTeamPlant.fromJson]).
  factory RedTeamBench.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('FIXTURE_NOT_JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException(
        'FIXTURE_NOT_OBJECT: top level must be a JSON object',
      );
    }
    final rawFloor = decoded['refusal_floor'];
    if (rawFloor != null &&
        (rawFloor is! int || rawFloor != preregRefusalFloor)) {
      throw FormatException(
        'REFUSAL_FLOOR_MISMATCH=$rawFloor: the PREREG-C V-4 floor is FROZEN '
        'at $preregRefusalFloor and cannot be edited via fixture',
      );
    }
    final rawLengthFloor = decoded['length_norm_floor'];
    if (rawLengthFloor == null) {
      throw const FormatException('MISSING_FIELD=length_norm_floor');
    }
    if (rawLengthFloor is! num || rawLengthFloor <= 0) {
      throw FormatException(
        'LENGTH_NORM_FLOOR_INVALID=$rawLengthFloor: must be a number > 0',
      );
    }
    final rawPlants = decoded['plants'];
    if (rawPlants == null) {
      throw const FormatException('MISSING_FIELD=plants');
    }
    if (rawPlants is! List) {
      throw const FormatException('MALFORMED_FIELD=plants expected=List');
    }
    final plants = <RedTeamPlant>[];
    final seen = <String>{};
    for (var i = 0; i < rawPlants.length; i++) {
      final entry = rawPlants[i];
      if (entry is! Map) {
        throw FormatException('MALFORMED_FIELD=plants[$i] expected=object');
      }
      final plant =
          RedTeamPlant.fromJson(Map<String, Object?>.from(entry), index: i);
      if (!seen.add(plant.id)) {
        throw FormatException('DUPLICATE_PLANT_ID=${plant.id}');
      }
      plants.add(plant);
    }
    return RedTeamBench._(
      plants: plants,
      lengthNormFloor: rawLengthFloor.toDouble(),
    );
  }

  /// Looks a plant up by id; an unknown id is a NAMED refusal
  /// (`UNKNOWN_PLANT_ID=`).
  RedTeamPlant plantById(String id) {
    for (final p in plants) {
      if (p.id == id) return p;
    }
    throw FormatException('UNKNOWN_PLANT_ID=$id');
  }

  /// Evaluates every plant (fixture order). The bypass flags are the
  /// mutation-check surface: each removes ONE guard condition from the
  /// verdict (the frozen sources are never touched).
  List<PlantResult> run({
    bool bypassInvariant = false,
    bool bypassLengthFloor = false,
    bool bypassMemorization = false,
  }) =>
      [
        for (final p in plants)
          evaluatePlant(
            p,
            bypassInvariant: bypassInvariant,
            bypassLengthFloor: bypassLengthFloor,
            bypassMemorization: bypassMemorization,
          ),
      ];

  /// Evaluates one plant: computes {naive, invariant, length_norm, memo_flag}
  /// with frozen scorers/probes only, then the verdict — `REFUSED` (any
  /// guard fires, reasons NAMED) else the class's NAMED leak.
  PlantResult evaluatePlant(
    RedTeamPlant plant, {
    bool bypassInvariant = false,
    bool bypassLengthFloor = false,
    bool bypassMemorization = false,
  }) {
    final naive = _naiveScore(plant);
    final scorer = _invariantScorer(plant);
    final frozenInvariant = formatInvariantScore(scorer, plant.output);
    final invariant = redteamInvariantScore(scorer, plant.output);
    final lengthNorm =
        lengthNormalized(plant.rawCorrectCells, plant.tokenCount);
    final capHit = tokenLimitRate([plant.tokenCount], plant.tokenCap);

    // Memorization: verbatim replay of the cell's expected answer AND a
    // frozen probe-bookkeeping refusal of the plant's probe sets.
    var memoFlag = false;
    var excluded = false;
    ProbeSetViolation? violation;
    if (plant.klass == RedTeamClass.memorization) {
      try {
        ProbeBookkeeping.assertDisjoint(plant.probeSets!);
      } on ProbeSetViolation catch (v) {
        violation = v;
      }
      final verbatim =
          plant.expectedAnswer != null && plant.output.contains(plant.expectedAnswer!);
      memoFlag = verbatim && violation != null;
      excluded = memoFlag;
    }

    final killer = invariant < naive
        ? firstWinBreakingPerturbation(scorer, plant.output, naive)
        : null;

    final reasons = <String>[];
    final effectiveInvariant = bypassInvariant ? naive : invariant;
    if (effectiveInvariant <= 0) {
      reasons.add(
        'FORMAT_INVARIANT_MIN_ZERO: naive=$naive invariant=$invariant '
        '(min over frozen surface perturbations + named case variants)'
        '${killer == null ? '' : '; killer=$killer'}',
      );
    }
    if (!bypassLengthFloor && lengthNorm < lengthNormFloor) {
      reasons.add(
        'LENGTH_NORMALIZED_BELOW_FLOOR: lengthNormalized('
        '${plant.rawCorrectCells}, ${plant.tokenCount}) = $lengthNorm < '
        'floor $lengthNormFloor',
      );
    }
    if (!bypassMemorization && memoFlag) {
      reasons.add(
        'MEMORIZATION_EXCLUDED: $violation; cell=${plant.cell!.name}; '
        'cue: ${plant.memorizationCue}',
      );
    }

    return PlantResult(
      plant: plant,
      naiveScore: naive,
      invariantScore: invariant,
      frozenInvariantScore: frozenInvariant,
      lengthNorm: lengthNorm,
      memoFlag: memoFlag,
      capHitRate: capHit,
      killerPerturbation: killer,
      refusalReasons: reasons,
      certificationExcluded: excluded,
      verdict: reasons.isEmpty ? plant.klass.leakVerdict : verdictRefused,
    );
  }

  /// Summarizes results against the FROZEN floor: `floor_met` iff all
  /// [preregRefusalFloor] plants were evaluated and every one was REFUSED.
  RedTeamSummary summarize(List<PlantResult> results) {
    final refusals = results.where((r) => r.refused).length;
    final byClass = <String, int>{
      for (final c in RedTeamClass.values)
        c.wire: results.where((r) => r.plant.klass == c && r.refused).length,
    };
    return RedTeamSummary(
      plantsEvaluated: results.length,
      refusals: refusals,
      leaks: results.length - refusals,
      floorMet:
          results.length == preregRefusalFloor && refusals == preregRefusalFloor,
      preregFloor: preregRefusalFloor,
      lengthNormFloor: lengthNormFloor,
      refusalsByClass: byClass,
      leaksNamed: [for (final r in results) if (!r.refused) r.verdict],
      excludedCells: [
        for (final r in results)
          if (r.certificationExcluded) r.plant.cell!.name,
      ],
    );
  }

  /// Receipt lines: one json line per plant (pre-registered fields first),
  /// then the summary line. [date] is stamped by the runner.
  List<String> receiptLines(List<PlantResult> results, {String? date}) {
    final summary = summarize(results);
    return [
      ...results.map((r) => jsonEncode(r.toJson())),
      jsonEncode(summary.toJson(date: date)),
    ];
  }

  double _naiveScore(RedTeamPlant plant) {
    switch (plant.naiveScorer) {
      case 'raw_cell_count_ignores_length':
        return plant.rawCorrectCells >= plant.cellsRequired ? 1.0 : 0.0;
      case 'gold_occurrence_count':
        return countWordBoundaryOccurrences(plant.output, plant.gold) >=
                plant.cellsRequired
            ? 1.0
            : 0.0;
      default:
        return _surfaceNaiveScorers[plant.naiveScorer]!(
          plant.output,
          plant.gold,
        );
    }
  }

  /// The scorer the invariant min is taken over: the plant's naive scorer
  /// when it consumes surface form; for count-based naive metrics (which
  /// never look at the surface) the content check UNDER the count — the
  /// frozen [mathScore] against the plant's gold.
  double Function(String) _invariantScorer(RedTeamPlant plant) {
    final surface = _surfaceNaiveScorers[plant.naiveScorer];
    if (surface != null) return (o) => surface(o, plant.gold);
    return (o) => mathScore(o, plant.gold).toDouble();
  }
}
