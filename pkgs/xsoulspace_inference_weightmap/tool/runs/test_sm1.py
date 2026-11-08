#!/usr/bin/env python3
"""test_sm1.py - CPU-only unit tests for the SM-1 runner's FROZEN pure parts
(PREREG-SM1 §2/§4; no mlx, no device). Run: python3 tool/runs/test_sm1.py -v
"""

import json
import os
import random
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import sm1_run as sm1  # noqa: E402


class TestSampling(unittest.TestCase):
    def setUp(self):
        # deterministic score vector: 16 nonzero, rest zero
        rng = random.Random(7)
        self.scores = [0.0] * 3584
        for c in range(16):
            self.scores[c * 3] = 1.0 + rng.random()

    def test_guided_draws_only_nonzero_k_sorted(self):
        cols = sm1.draw_guided(self.scores, 8, random.Random(1))
        self.assertEqual(len(cols), 8)
        self.assertEqual(len(set(cols)), 8)
        for c in cols:
            self.assertGreater(self.scores[c], 0.0)
        self.assertEqual(cols, sorted(cols))

    def test_guided_deterministic_seeded(self):
        a = sm1.draw_guided(self.scores, 8, random.Random(42))
        b = sm1.draw_guided(self.scores, 8, random.Random(42))
        self.assertEqual(a, b)

    def test_guided_fails_when_support_too_small(self):
        with self.assertRaises(RuntimeError):
            sm1.draw_guided([0.0] * 3584, 8, random.Random(1))

    def test_sample_plan_shape_and_blindness(self):
        plan = sm1.sample_columns(self.scores, 3584, sm1.SEED_DEFAULT)
        arms = [s['arm'] for s in plan]
        self.assertEqual(arms.count('GUIDED'), sm1.N_GUIDED)
        self.assertEqual(arms.count('RANDOM'), sm1.N_RANDOM)
        self.assertEqual(arms.count('SHUFFLED'), sm1.N_SHUFFLED)
        for s in plan:
            self.assertEqual(len(s['columns']), sm1.K_COLS)
            self.assertEqual(s['columns'], sorted(set(s['columns'])))
        # plan is a pure function of (scores, seed): same seed => same plan
        again = sm1.sample_columns(self.scores, 3584, sm1.SEED_DEFAULT)
        self.assertEqual(plan, again)

    def test_shuffle_preserves_score_multiset(self):
        sh = sm1.shuffled_scores(self.scores, 99)
        self.assertEqual(sorted(sh), sorted(self.scores))
        self.assertNotEqual(sh, self.scores)  # permutation actually moves


class TestFitness(unittest.TestCase):
    def test_paired_improvement(self):
        rows = [{'cap_hit': True}, {'cap_hit': False}, {'cap_hit': True},
                {'cap_hit': False}, {'cap_hit': False}, {'cap_hit': True}]
        # addendum 2026-11-08c: fitness = base_hits - sample hits
        self.assertEqual(sm1.fitness_from_rows(rows, 6), 3)
        self.assertEqual(sm1.fitness_from_rows(rows, 4), 1)
        self.assertEqual(sm1.fitness_from_rows(rows, 3), 0)  # no improvement


class TestVerdictClasses(unittest.TestCase):
    def base(self, hits=6):
        return hits

    def rows(self, guided, rnd, shuf):
        out = []
        for arm, fits in (('GUIDED', guided), ('RANDOM', rnd),
                          ('SHUFFLED', shuf)):
            for i, f in enumerate(fits):
                out.append({'kind': 'sample_complete', 'arm': arm,
                            'idx': i, 'fitness': f})
        return out

    def test_no_sample_improves(self):
        v = sm1.verdict_classes(self.rows([0] * 3, [0] * 3, [0]),
                                self.base(6), True, True)
        self.assertEqual(v['verdict'], 'NO_SAMPLE_IMPROVES')

    def test_guided_beats_random_with_chance_ok(self):
        v = sm1.verdict_classes(self.rows([4, 3, 2], [1, 0, 1], [1]),
                                self.base(6), True, True)
        self.assertEqual(v['verdict'], 'GUIDED_BEATS_RANDOM')
        self.assertEqual(v['chance_control'], 'CHANCE_CONTROL_OK')

    def test_chance_control_leak_named(self):
        v = sm1.verdict_classes(self.rows([4, 3, 2], [1, 0, 1], [4]),
                                self.base(6), True, True)
        self.assertEqual(v['verdict'], 'GUIDED_BEATS_RANDOM')
        self.assertEqual(v['chance_control'], 'CHANCE_CONTROL_LEAK')

    def test_no_signal_when_random_matches_guided(self):
        v = sm1.verdict_classes(self.rows([2, 2, 2], [2, 1, 2], [2]),
                                self.base(6), True, True)
        self.assertEqual(v['verdict'], 'NO_SIGNAL')

    def test_determinism_drift_caps_everything(self):
        v = sm1.verdict_classes(self.rows([4, 4, 4], [0, 0, 0], [0]),
                                self.base(6), False, True)
        self.assertEqual(v['verdict'], 'DETERMINISM_DRIFT')

    def test_partial_when_no_guided(self):
        v = sm1.verdict_classes(self.rows([], [1, 0], []), self.base(6),
                                None, False)
        self.assertEqual(v['verdict'],
                         'PARTIAL_WITH_DENOMINATOR_NO_GUIDED_SAMPLES')


class TestFirstLineScorers(unittest.TestCase):
    def test_label_case_insensitive(self):
        cell = {'scorer': 'label_first_line', 'gold': 'Allow'}
        self.assertTrue(sm1.score_first_line(cell, 'allow\nbecause'))
        self.assertFalse(sm1.score_first_line(cell, 'deny\nbecause'))

    def test_string_quotes_and_period(self):
        cell = {'scorer': 'string_first_line', 'gold': 'camelToSnake'}
        # frozen convention order (a3_score.dart): quote-strip fires only
        # when the FIRST and LAST chars are quotes; a trailing period after
        # a quoted answer therefore does NOT strip — documented quirk.
        self.assertTrue(sm1.score_first_line(cell, '"camelToSnake"'))
        self.assertFalse(sm1.score_first_line(cell, '"camelToSnake".'))
        self.assertTrue(sm1.score_first_line(cell, 'camelToSnake.'))
        self.assertFalse(sm1.score_first_line(cell, 'camel_to_snake'))

    def test_think_prefix_stripped(self):
        cell = {'scorer': 'label_first_line', 'gold': 'allow'}
        self.assertTrue(sm1.score_first_line(
            cell, '<think>blah</think>\n\nallow\nx'))


class TestChain(unittest.TestCase):
    def test_append_verify_round_trip_and_tamper(self):
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, 'SM1-test.jsonl')
            sm1.chain_append(path, 'a', {'x': 1})
            sm1.chain_append(path, 'b', {'y': [2, 3]})
            self.assertTrue(sm1.chain_verify(path).startswith('CHAIN_INTACT'))
            rows = [json.loads(ln) for ln in open(path)]
            rows[0]['payload']['x'] = 999   # tamper
            with open(path, 'w') as fh:
                for r in rows:
                    fh.write(json.dumps(r) + '\n')
            self.assertTrue(sm1.chain_verify(path)
                            .startswith('CHAIN_BROKEN_AT=0'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
