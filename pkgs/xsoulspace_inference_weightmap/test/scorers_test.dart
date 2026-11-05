// Fixtures for the frozen scorer surface (PREREG-A A4 scope): extraction,
// numeric equivalence, suite wrappers, IFEval-style checks, token-limit rate,
// the format-invariance guard, and length normalization.
//
// The two guard semantics the program exists for:
// - perturbation invariance: a fenced vs unfenced correct answer scores EQUAL,
//   and a format-only "win" dies under the min;
// - length normalization: a long wrong output must NEVER outscore a short
//   correct one.
import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/scorers.dart';

void main() {
  group('extractFinalAnswer', () {
    test('prefers the boxed group', () {
      expect(extractFinalAnswer(r'The answer is \boxed{42}.'), '42');
    });

    test('boxed with nested braces (frac) is brace-matched', () {
      expect(
        extractFinalAnswer(r'answer is \boxed{\frac{1}{2}} and done'),
        r'\frac{1}{2}',
      );
    });

    test('last boxed wins (final-answer convention)', () {
      expect(extractFinalAnswer(r'\boxed{1} then \boxed{2}'), '2');
    });

    test('unbalanced boxed falls through to the numeric scan, never crashes',
        () {
      expect(extractFinalAnswer(r'The \boxed{42'), isNull);
    });

    test('falls back to the last numeric-looking token', () {
      expect(extractFinalAnswer('So the total is 42 dollars.'), '42');
      expect(extractFinalAnswer('Answer: 1,234.'), '1,234');
      expect(extractFinalAnswer('about 25% of cases'), '25%');
      expect(extractFinalAnswer('the ratio is 3/4 exactly'), '3/4');
      expect(extractFinalAnswer(r'costs $18 in total'), '18');
      expect(extractFinalAnswer('negative -7 degrees'), '-7');
    });

    test('edge cases: no answer, empty, garbage -> null, not crash', () {
      expect(extractFinalAnswer(''), isNull);
      expect(extractFinalAnswer('I do not know the answer.'), isNull);
      expect(extractFinalAnswer('\u0000\uffff garbage \n\t'), isNull);
    });
  });

  group('mathEquivalent', () {
    test('numeric normalization: decimals, ints, commas, percents', () {
      expect(mathEquivalent('42', '42.0'), isTrue);
      expect(mathEquivalent('1,000', '1000'), isTrue);
      expect(mathEquivalent('1,234,567', '1234567'), isTrue);
      expect(mathEquivalent(r'50\%', '50'), isTrue);
      expect(mathEquivalent('50%', '50'), isTrue);
      expect(mathEquivalent('5.', '5'), isTrue);
      expect(mathEquivalent('+7', '7'), isTrue);
      expect(mathEquivalent('(42)', '42'), isTrue);
    });

    test('fractions: plain a/b and \\frac{a}{b}', () {
      expect(mathEquivalent('3/4', '0.75'), isTrue);
      expect(mathEquivalent(r'\frac{1}{2}', '0.5'), isTrue);
      expect(mathEquivalent(r'\dfrac{-3}{4}', '-0.75'), isTrue);
      expect(mathEquivalent('1/3', '0.333333'), isTrue); // 1e-6 tolerance
      expect(mathEquivalent('2/3', '0.5'), isFalse);
    });

    test('tolerance band: near-equal passes, clearly different fails', () {
      expect(mathEquivalent('2.0000001', '2'), isTrue);
      expect(mathEquivalent('2.1', '2'), isFalse);
    });

    test('sqrt/pi forms use the normalized string fallback', () {
      expect(mathEquivalent(r'\sqrt{2}', 'sqrt(2)'), isTrue);
      expect(mathEquivalent(r'2\pi', '2pi'), isTrue);
      expect(mathEquivalent(r'\sqrt{2}', r'\sqrt{3}'), isFalse);
    });

    test('text answers normalize; mismatches stay false; empty never crashes',
        () {
      expect(mathEquivalent(r'\text{yes}', 'yes'), isTrue);
      expect(mathEquivalent('no', 'yes'), isFalse);
      expect(mathEquivalent('', '42'), isFalse);
      expect(mathEquivalent('42', ''), isFalse);
    });
  });

  group('mathScore / gsm8kScore wrappers', () {
    test('mathScore: boxed correct -> 1, wrong -> 0', () {
      expect(mathScore(r'reasoning... \boxed{42}', '42'), 1);
      expect(mathScore(r'reasoning... \boxed{41}', '42'), 0);
    });

    test('mathScore: sees through fences and trailing decoration', () {
      expect(mathScore('```\nThe answer is 42.\n```', '42'), 1);
    });

    test('mathScore: no extractable answer -> 0, not crash', () {
      expect(mathScore('I am not sure about this one.', '42'), 0);
      expect(mathScore('', '42'), 0);
    });

    test('gsm8kScore: plain numeric gold, last-number extraction', () {
      expect(gsm8kScore('First 10, then 8 more, total 18.', '18'), 1);
      expect(gsm8kScore('#### style: 1,234 apples', '1,234'), 1);
      expect(gsm8kScore('The answer is 17.', '18'), 0);
      expect(gsm8kScore('no numbers at all', '18'), 0);
    });
  });

  group('ifeval checks', () {
    test('word_count_bound: pass and fail', () {
      final spec = WordCountBound(minWords: 3, maxWords: 5);
      expect(spec.check('one two three four'), isTrue);
      expect(spec.check('one'), isFalse);
      expect(spec.check('one two three four five six'), isFalse);
      expect(spec.checkReason('one')!, contains('word_count_bound'));
    });

    test('word_count_bound: bad bounds refuse with named ArgumentError', () {
      expect(
        () => WordCountBound(),
        throwsA(predicate(
          (Object e) => e.toString().contains('WORD_COUNT_BOUND_EMPTY'),
        )),
      );
      expect(
        () => WordCountBound(minWords: 5, maxWords: 3),
        throwsA(predicate(
          (Object e) => e.toString().contains('WORD_COUNT_BOUND_INVERTED'),
        )),
      );
      expect(
        () => WordCountBound(minWords: -1),
        throwsA(predicate(
          (Object e) => e.toString().contains('WORD_COUNT_BOUND_NEGATIVE'),
        )),
      );
    });

    test('keyword_include: all keywords, case-insensitive', () {
      final spec = KeywordInclude(['Dart', 'score']);
      expect(spec.check('a dart SCORE keeper'), isTrue);
      expect(spec.check('only dart here'), isFalse);
      expect(spec.checkReason('only dart here')!, contains('score'));
    });

    test('keyword_exclude: any forbidden keyword fails', () {
      final spec = KeywordExclude(['sorry', 'apologize']);
      expect(spec.check('a clean answer'), isTrue);
      expect(spec.check('I am SORRY about that'), isFalse);
      expect(spec.checkReason('I am sorry')!, contains('keyword_exclude'));
    });

    test('json_only: whole output must parse as one JSON value', () {
      const spec = JsonOnlyOutput();
      expect(spec.check('{"a": 1}'), isTrue);
      expect(spec.check('  [1, 2, 3]\n'), isTrue);
      expect(spec.check('null'), isTrue);
      expect(spec.check('{"a": 1} trailing prose'), isFalse);
      expect(spec.check(''), isFalse);
    });

    test('bullet_list: bullets or numbered items, min items enforced', () {
      final spec = BulletListFormat(minItems: 2);
      expect(spec.check('- first\n- second'), isTrue);
      expect(spec.check('* first\n* second'), isTrue);
      expect(spec.check('1. first\n2. second'), isTrue);
      expect(spec.check('- first\nplain line'), isFalse);
      expect(spec.check('- only one'), isFalse);
      expect(spec.checkReason('- only one')!, contains('bullet_list'));
    });

    test('starts_with: exact, case-sensitive, no trim', () {
      final spec = StartsWithPrefix('Answer:');
      expect(spec.check('Answer: 42'), isTrue);
      expect(spec.check('answer: 42'), isFalse);
      expect(spec.check(' Answer: 42'), isFalse);
    });

    test('uppercase_title_line: first non-empty line is ALL CAPS', () {
      const spec = UppercaseTitleLine();
      expect(spec.check('TITLE OF WORK\nbody text here'), isTrue);
      expect(spec.check('\n\nCAPS TITLE 2!\nbody'), isTrue);
      expect(spec.check('Title Case\nbody'), isFalse);
      expect(spec.check('12345\nbody'), isFalse); // no letters
      expect(spec.check(''), isFalse);
    });

    test('empty keyword lists refuse with named ArgumentError', () {
      expect(
        () => KeywordInclude([]),
        throwsA(predicate((Object e) => e.toString().contains('KEYWORDS_EMPTY'))),
      );
      expect(
        () => KeywordExclude([]),
        throwsA(predicate((Object e) => e.toString().contains('KEYWORDS_EMPTY'))),
      );
    });

    test('ifevalChecks names every failure; ifevalScore is 0/1', () {
      final specs = <IfevalSpec>[
        WordCountBound(minWords: 100),
        KeywordInclude(['mustappear']),
        const JsonOnlyOutput(),
      ];
      const output = 'a short prose answer';
      final failures = ifevalChecks(specs, output);
      expect(failures.map((f) => f.check), [
        'word_count_bound',
        'keyword_include',
        'json_only',
      ]);
      expect(failures.every((f) => f.detail.isNotEmpty), isTrue);
      expect(ifevalScore(specs, output), 0);
      expect(ifevalScore(const [], output), 1);
      expect(
        ifevalScore([WordCountBound(minWords: 2)], 'two words'),
        1,
      );
    });
  });

  group('tokenLimitRate', () {
    test('fraction of outputs at or above the cap', () {
      expect(tokenLimitRate([32768, 100, 32768, 32767], 32768), 0.5);
      expect(tokenLimitRate([10, 20], 32768), 0.0);
      expect(tokenLimitRate([32768], 32768), 1.0);
    });

    test('named refusals, never silent zeros', () {
      expect(
        () => tokenLimitRate([], 100),
        throwsA(predicate(
          (Object e) => e.toString().contains('EMPTY_TOKEN_SAMPLE'),
        )),
      );
      expect(
        () => tokenLimitRate([1], 0),
        throwsA(predicate((Object e) => e.toString().contains('NONPOSITIVE_CAP'))),
      );
      expect(
        () => tokenLimitRate([1, -5], 10),
        throwsA(predicate(
          (Object e) => e.toString().contains('NEGATIVE_TOKEN_COUNT'),
        )),
      );
    });
  });

  group('formatInvariantScore (the false-positive guard)', () {
    double Function(String) mathScorer(String gold) =>
        (String o) => mathScore(o, gold).toDouble();

    test('fenced vs unfenced correct answer score EQUAL', () {
      const unfenced = 'The reasoning gives 42 as the result. So: 42';
      const fenced = '```\nThe reasoning gives 42 as the result. So: 42\n```';
      final score = mathScorer('42');
      expect(formatInvariantScore(score, fenced),
          formatInvariantScore(score, unfenced));
      expect(formatInvariantScore(score, fenced), 1.0);
      expect(formatInvariantScore(score, unfenced), 1.0);
    });

    test('trailing whitespace and blank-line padding do not change the score',
        () {
      final score = mathScorer('42');
      const padded = 'The answer is 42.   \n\n\n  \n';
      expect(formatInvariantScore(score, padded), 1.0);
    });

    test('a format-only win dies under the min', () {
      // A scorer that rewards ONLY fenced output (the format-artifact
      // false positive this repo has paid for): identity passes, but the
      // strip-one-fence-pair perturbation exposes it -> min is 0.
      double onlyFencedLooksRight(String o) =>
          o.trimLeft().startsWith('```') ? 1.0 : 0.0;
      expect(formatInvariantScore(onlyFencedLooksRight, '```\n42\n```'), 0.0);
    });

    test('surfacePerturbations is the four named surface transforms', () {
      final names = surfacePerturbations('x').map((p) => p.name).toList();
      expect(names, [
        'identity',
        'trim_trailing_whitespace',
        'strip_one_fence_pair',
        'collapse_blank_lines',
      ]);
      expect(stripOneFencePair('```\n42\n```'), '42');
      expect(stripOneFencePair('no fences here'), 'no fences here');
      expect(collapseBlankLines('a\n\n\nb'), 'a\nb');
      expect(collapseBlankLines('a\nb'), 'a\nb');
    });
  });

  group('lengthNormalized', () {
    test('long wrong output NEVER outscores short correct output', () {
      final shortCorrect = lengthNormalized(1, 50);
      final longWrong = lengthNormalized(0, 5000);
      expect(longWrong, lessThan(shortCorrect));
      expect(longWrong, 0.0);
    });

    test('verbosity is penalized even when the correct count is equal', () {
      expect(lengthNormalized(3, 300), greaterThan(lengthNormalized(3, 3000)));
      expect(lengthNormalized(1, 50), closeTo(0.02, 1e-12));
      expect(lengthNormalized(1, 5000), greaterThan(lengthNormalized(1, 50000)));
    });

    test('named refusals on undefined rates', () {
      expect(
        () => lengthNormalized(1, 0),
        throwsA(predicate(
          (Object e) => e.toString().contains('NONPOSITIVE_TOKEN_TOTAL'),
        )),
      );
      expect(
        () => lengthNormalized(-1, 10),
        throwsA(predicate(
          (Object e) => e.toString().contains('NEGATIVE_CORRECT_CELLS'),
        )),
      );
    });
  });
}
