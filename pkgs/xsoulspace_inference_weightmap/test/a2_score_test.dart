/// A2-LOCAL scorer cross-check (PREREG-A arm A2).
///
/// 20+ HAND-SCORED rows: every expectation below was derived by hand from
/// the frozen `lib/src/scorers.dart` semantics (extraction rule, numeric
/// equivalence, sealed IfevalSpec checks, tokenLimitRate refusals) BEFORE
/// running, and asserts that `tool/runs/a2_score.dart` wires those frozen
/// scorers without drift. The frozen file itself is never edited (A4 law).
///
/// Hand-derivation notes for the non-obvious rows:
///  - M2: `\boxed{\frac{3}{4}}` normalizes to `(3)/(4)` -> 0.75 == gold 0.75
///    within 1e-6 relative tolerance.
///  - M3: token `1,234.` -> trailing decoration `.` stripped -> `1,234`
///    matches the thousands-comma numeric form -> 1234.
///  - M5: token `50%.` -> decoration strip -> `50%` -> percent stripped in
///    normalization -> 50 (MATH-suite convention).
///  - M6: unbalanced `\boxed{42` is skipped by the balanced-group scanner;
///    the raw token is not numeric -> no answer -> 0 (never crashes).
///  - M9: exp8 convention — a `\boxed{7}` INSIDE the thinking block does not
///    count: the scorer input is the text after the last `</think>`; the
///    answer part has no numeric token -> 0.
///  - M10: `12\%` normalizes `\%` -> `%` -> stripped -> 12.
///  - I6: fenced JSON fails the frozen JsonOnlyOutput (dart:convert on the
///    trimmed whole output) — STRICTER than the official IFEval checker;
///    this is the documented JSON_NO_FENCE_STRIP mapping caveat.
///  - I8: prose line before the bullets fails the frozen BulletListFormat
///    (every non-empty line must be an item) — documented
///    BULLET_SEMANTICS_STRICTER caveat.
///  - I13: thinking-on with no `</think>` -> empty answer (exp8 grade_other
///    convention) -> word-count check fails, answer_empty flagged.
///  - T1: cap-hit is `count >= cap`: 4096 and 8192 hit at cap 4096; 4095
///    does not -> 2/4 = 0.5.
///  - W1/W2: Wilson 95% (z=1.959964) hand-computed: k=0,n=100 -> hi=0.03699;
///    k=50,n=100 -> (0.40383, 0.59617).
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/scorers.dart';

import '../tool/runs/a2_score.dart';

GenRow row(String output, {int tokens = 0, bool hit = false}) => (
  promptId: 0,
  prompt: 'p',
  outputText: output,
  outputTokens: tokens,
  hitTokenLimit: hit,
  finishReason: hit ? 'length' : 'stop',
  wallMs: 0,
);

Map<String, dynamic> mathGold(String gold) => {'prompt': 'p', 'gold': gold};

/// Realistic IFEval generation shape: the prompt pre-fills `<think>`, so a
/// finished answer always carries the think-close marker; the scorer input is
/// the post-marker text (exp8 grade_other convention).
String think(String answer) => '<think>reasoning here</think> $answer';

Map<String, dynamic> ifeGold(List<Map<String, Object?>> specs) =>
    {'prompt': 'p', 'specs': specs};

void main() {
  group('answerAfterThink (scoring-input mapping)', () {
    test('cuts at the LAST think-close and trims', () {
      expect(answerAfterThink('a</think>b</think> c '), 'c');
    });
    test('full text when no marker', () {
      expect(answerAfterThink('no think here'), 'no think here');
    });
    test('empty when missing and emptyWhenMissing (IFEval thinking-on)', () {
      expect(answerAfterThink('think only', emptyWhenMissing: true), '');
    });
  });

  group('hand-scored MATH rows (frozen mathScore)', () {
    final cases = <(String, String, int)>[
      // M1 plain boxed
      (r'Step 1... The answer is \boxed{42}', '42', 1),
      // M2 latex fraction vs decimal gold
      (r'so \boxed{\frac{3}{4}}', '0.75', 1),
      // M3 no boxed, thousands-comma token with trailing period
      ('The answer is 1,234.', '1234', 1),
      // M4 LAST boxed wins
      (r'\boxed{7} then \boxed{9}', '9', 1),
      // M5 percent token
      ('The answer is 50%.', '50', 1),
      // M6 unbalanced boxed -> no answer -> 0
      (r'\boxed{42', '42', 0),
      // M7 sqrt symbolic string fallback
      (r'\boxed{\sqrt{2}}', r'\sqrt{2}', 1),
      // M8 no numeric content at all
      ('I cannot answer.', '5', 0),
      // M9 boxed inside thinking does NOT count (answer_text convention)
      ('<think>reasoning \\boxed{7}</think> The final result is computed.', '7', 0),
      // M10 escaped percent inside boxed
      (r'answer: \boxed{12\%}', '12', 1),
    ];
    for (var i = 0; i < cases.length; i++) {
      final (output, gold, expected) = cases[i];
      test('M${i + 1}', () {
        expect(scoreOneRow('math', row(output), mathGold(gold)).score, expected);
      });
    }
  });

  group('hand-scored GSM8K rows (frozen gsm8kScore)', () {
    final cases = <(String, String, int)>[
      ('So the answer is 18', '18', 1), // G1 bare final number
      ('total is 1,000 apples', '1000', 1), // G2 thousands comma
      (r'the answer is \boxed{25}', '26', 0), // G3 wrong boxed
      ('', '5', 0), // G4 empty output -> no answer
    ];
    for (var i = 0; i < cases.length; i++) {
      final (output, gold, expected) = cases[i];
      test('G${i + 1}', () {
        expect(
          scoreOneRow('gsm8k', row(output), mathGold(gold)).score,
          expected,
        );
      });
    }
  });

  group('hand-scored IFEval rows (frozen IfevalSpec subset)', () {
    test('I1 word_count min pass', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('one two three four five six')),
          ifeGold([
            {'t': 'word_count', 'min': 5},
          ]),
        ).score,
        1,
      );
    });
    test('I2 word_count min fail', () {
      final r = scoreOneRow(
        'ifeval',
        row(think('one two three')),
        ifeGold([
          {'t': 'word_count', 'min': 5},
        ]),
      );
      expect(r.score, 0);
      expect((r.detail['fails'] as List).single['check'], 'word_count_bound');
    });
    test('I3 keyword_include case-insensitive pass', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('The Alpha and the BETA.')),
          ifeGold([
            {'t': 'kw_include', 'kw': ['alpha', 'beta']},
          ]),
        ).score,
        1,
      );
    });
    test('I4 keyword_include missing one -> fail', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('alpha only')),
          ifeGold([
            {'t': 'kw_include', 'kw': ['alpha', 'beta']},
          ]),
        ).score,
        0,
      );
    });
    test('I5 json_only bare object pass', () {
      expect(
        scoreOneRow('ifeval', row(think('{"a": 1}')), ifeGold([
          {'t': 'json_only'},
        ])).score,
        1,
      );
    });
    test('I6 json_only FENCED fails (stricter-than-official caveat)', () {
      expect(
        scoreOneRow('ifeval', row(think('```json\n{"a": 1}\n```')), ifeGold([
          {'t': 'json_only'},
        ])).score,
        0,
      );
    });
    test('I7 bullet_list pass', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('- first\n- second')),
          ifeGold([
            {'t': 'bullet_list', 'min_items': 2},
          ]),
        ).score,
        1,
      );
    });
    test('I8 bullet_list with prose line fails (strict caveat)', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('Intro line\n- a\n- b')),
          ifeGold([
            {'t': 'bullet_list', 'min_items': 2},
          ]),
        ).score,
        0,
      );
    });
    test('I9 upper_title pass (thinking stripped first)', () {
      expect(
        scoreOneRow(
          'ifeval',
          row('<think>hmm</think>MY TITLE\nbody text here'),
          ifeGold([
            {'t': 'upper_title'},
          ]),
        ).score,
        1,
      );
    });
    test('I10 upper_title mixed case fail', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('My Title\nbody')),
          ifeGold([
            {'t': 'upper_title'},
          ]),
        ).score,
        0,
      );
    });
    test('I11 kw_exclude pass', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('stone music')),
          ifeGold([
            {'t': 'kw_exclude', 'kw': ['rock']},
          ]),
        ).score,
        1,
      );
    });
    test('I12 kw_exclude fail', () {
      expect(
        scoreOneRow(
          'ifeval',
          row(think('rock music')),
          ifeGold([
            {'t': 'kw_exclude', 'kw': ['rock']},
          ]),
        ).score,
        0,
      );
    });
    test('I13 thinking-on, no think-close -> empty answer -> fail', () {
      final r = scoreOneRow(
        'ifeval',
        row('<think>looping forever...', tokens: 4096, hit: true),
        ifeGold([
          {'t': 'word_count', 'min': 1},
        ]),
      );
      expect(r.score, 0);
      expect(r.detail['answer_empty'], true);
    });
  });

  group('hand-scored token-limit rows (frozen tokenLimitRate)', () {
    test('T1 cap-hit is count >= cap', () {
      expect(tokenLimitRate([4096, 100, 4095, 8192], 4096), 0.5);
    });
    test('T2 all hit', () {
      expect(tokenLimitRate([8192, 8192], 8192), 1.0);
    });
    test('T3 empty sample is a named refusal, not 0', () {
      expect(() => tokenLimitRate([], 4096), throwsArgumentError);
    });
    test('T4 nonpositive cap is a named refusal', () {
      expect(() => tokenLimitRate([10], 0), throwsArgumentError);
    });
  });

  group('Wilson 95% (hand-computed)', () {
    test('W1 k=0 n=100', () {
      final ci = wilson95(0, 100);
      expect(ci.lo, closeTo(0.0, 1e-9));
      expect(ci.hi, closeTo(0.03699, 0.0005));
    });
    test('W2 k=50 n=100', () {
      final ci = wilson95(50, 100);
      expect(ci.lo, closeTo(0.40383, 0.0005));
      expect(ci.hi, closeTo(0.59617, 0.0005));
    });
    test('W3 n=0 refused', () {
      expect(() => wilson95(0, 0), throwsArgumentError);
    });
  });

  group('spec parsing', () {
    test('SPEC_UNKNOWN is a named refusal', () {
      expect(
        () => parseSpecs([
          {'t': 'no_such_check'},
        ]),
        throwsA(isA<FormatException>()),
      );
    });
    test('all seven frozen spec types parse', () {
      final specs = parseSpecs([
        {'t': 'word_count', 'min': 1, 'max': 10},
        {'t': 'kw_include', 'kw': ['a']},
        {'t': 'kw_exclude', 'kw': ['b']},
        {'t': 'json_only'},
        {'t': 'bullet_list', 'min_items': 2},
        {'t': 'starts_with', 'prefix': 'Hi'},
        {'t': 'upper_title'},
      ]);
      expect(specs.length, 7);
      expect(specs.map((s) => s.checkName).toSet(), {
        'word_count_bound',
        'keyword_include',
        'keyword_exclude',
        'json_only',
        'bullet_list',
        'starts_with',
        'uppercase_title_line',
      });
    });
  });
}
