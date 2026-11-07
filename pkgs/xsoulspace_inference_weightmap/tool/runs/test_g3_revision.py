#!/usr/bin/env python3
"""test_g3_revision.py - CPU-only unit tests for the G-3 runner (no mlx,
no device). Run: python3 tool/runs/test_g3_revision.py [-v]

Pins (house law: golden mismatch = named refusal, never fix-in-place):
  1. the FROZEN detector (PREREG-G §3) against g3_detector_golden.json -
     expectations hand-computed pre-run;
  2. first_occurrence_end / rewind rule (§1 R3);
  3. NULL-A intervention schedule + seeded rewind determinism (§1);
  4. R1 context-set rule (§1);
  5. dry-run plan shape end-to-end via subprocess (no mlx import on the
     orchestrator path; exit 0; frozen constants + cells digest echoed).
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import g3_revision as g3  # noqa: E402


def golden():
    with open(os.path.join(HERE, 'g3_detector_golden.json'),
              encoding='utf-8') as fh:
        return json.load(fh)


class TestDetectorGolden(unittest.TestCase):
    def test_vectors(self):
        g = golden()
        self.assertEqual([g['params']['n'], g['params']['window'],
                          g['params']['threshold']],
                         [g3.DET_N, g3.DET_WINDOW, g3.DET_THRESHOLD],
                         'golden params drifted from frozen constants')
        for v in g['vectors']:
            with self.subTest(vector=v['name']):
                self.assertEqual(g3.loop_triggers(v['ids']), v['triggers'])

    def test_runtime_incremental_equals_offline(self):
        # the runtime check (detector_fires_at on the growing prefix) must
        # agree with the offline scorer form on every golden vector
        for v in golden()['vectors']:
            with self.subTest(vector=v['name']):
                ids = v['ids']
                runtime = [t for t in range(len(ids))
                           if g3.detector_fires_at(ids[:t + 1])]
                self.assertEqual(runtime, v['triggers'])


class TestRewindRule(unittest.TestCase):
    def test_first_occurrence_end(self):
        # period-8 pattern: trigger at t=19 on gram [1,2,3,4] whose first
        # occurrence starts at 0 => rewind_to = 4 (keep the first legit one)
        ids = [1, 2, 3, 4, 5, 6, 7, 8] * 3
        self.assertEqual(g3.first_occurrence_end(ids, 19), 4)

    def test_rewind_never_exceeds_trigger(self):
        ids = [7] * 8
        t = 5
        self.assertLessEqual(g3.first_occurrence_end(ids, t), t + 1)
        self.assertEqual(g3.first_occurrence_end(ids, t), 4)  # p0=0


class TestNullA(unittest.TestCase):
    def test_schedule_and_bounds(self):
        for L in (49, 97, 145):
            r = g3.nulla_rewind_to(L, cell_idx=3, int_idx=1,
                                   seed=g3.SEED_DEFAULT)
            self.assertGreaterEqual(r, max(0, L - g3.NULLA_BACK))
            self.assertLess(r, L - g3.NULLA_MIN_KEEP_BACK + 1)

    def test_deterministic_seeded(self):
        a = g3.nulla_rewind_to(100, 2, 1, g3.SEED_DEFAULT)
        b = g3.nulla_rewind_to(100, 2, 1, g3.SEED_DEFAULT)
        self.assertEqual(a, b)
        # different intervention index => (almost surely) different draw
        c = g3.nulla_rewind_to(100, 2, 2, g3.SEED_DEFAULT)
        self.assertIsInstance(c, int)

    def test_short_span_edge(self):
        # L small enough that the window collapses: returns lo, never raises
        self.assertEqual(g3.nulla_rewind_to(9, 0, 0, g3.SEED_DEFAULT), 0)

    def test_resample_seed_formula(self):
        self.assertEqual(
            g3.resample_seed(20261107, 5, 2),
            20261107 * 1000003 + 5 * 1009 + 2)


class TestRepPenaltyContext(unittest.TestCase):
    def test_context_set(self):
        seq = list(range(100)) + [7, 7, 8]   # last four: [99, 7, 7, 8]
        self.assertEqual(g3.rep_penalty_indices(seq, 4), [7, 8, 99])

    def test_context_window_bound(self):
        seq = list(range(200))
        self.assertEqual(g3.rep_penalty_indices(seq, 64),
                         list(range(136, 200)))


class TestDryRunPlan(unittest.TestCase):
    def test_plan_shape(self):
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, 'run')
            model = os.path.join(td, 'model')
            os.makedirs(model)
            # the orchestrator validates the base receipt only when present;
            # a bare dir exercises BASE_MODEL present + dry-run path
            proc = subprocess.run(
                [sys.executable, '-I', os.path.join(HERE,
                                                    'g3_revision.py'),
                 '--model', model, '--out', out, '--dry-run'],
                capture_output=True, text=True,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            plan = json.loads(proc.stdout)
            self.assertEqual(plan['mode'], 'dry-run')
            self.assertEqual(plan['cells_sha256'], g3.CELLS_SHA256_FROZEN)
            self.assertEqual(plan['arms'], g3.ARMS_FROZEN)
            self.assertEqual(plan['constants']['detector'], [4, 64, 3])
            self.assertEqual(len(plan['cells_selected']), 20)  # 12 G2 + 8 G0
            groups = {g for _i, g, _c in plan['cells_selected']}
            self.assertEqual(groups, {'G2', 'G0'})
            self.assertFalse(os.path.exists(out))  # nothing written

    def test_cells_digest_drift_named(self):
        with tempfile.TemporaryDirectory() as td:
            bad = os.path.join(td, 'cells.json')
            with open(bad, 'w', encoding='utf-8') as fh:
                fh.write('{"cells": {}}')
            proc = subprocess.run(
                [sys.executable, '-I',
                 os.path.join(HERE, 'g3_revision.py'),
                 '--model', td, '--cells', bad, '--dry-run'],
                capture_output=True, text=True,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual(proc.returncode, 1)
            self.assertIn('CELLS_DIGEST_DRIFT', proc.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
