#!/usr/bin/env python3
"""test_seq_stop.py - CPU-only pins for L5 always-valid stopping."""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import seq_stop as sq  # noqa: E402


class TestHalfwidth(unittest.TestCase):
    def test_known_values(self):
        # hand-computed: sqrt(ln(2/0.05)/(2*100)) = sqrt(2.9957/200)
        import math
        want = math.sqrt(math.log(2 / 0.05) / 200)
        self.assertAlmostEqual(sq.halfwidth(100, 0.05), want, places=12)

    def test_shrinks_with_n(self):
        self.assertLess(sq.halfwidth(400, 0.05), sq.halfwidth(100, 0.05))

    def test_input_guards(self):
        with self.assertRaises(ValueError):
            sq.halfwidth(0, 0.05)
        with self.assertRaises(ValueError):
            sq.halfwidth(10, 1.5)


class TestStopDecision(unittest.TestCase):
    def test_decisively_below_stops(self):
        # 0 passes in 400 cells at alpha=0.05: hi = sqrt(ln40)/800 ≈ .0193
        stop, why = sq.stop_decision(0, 400, 0.10, 0.05, 'below')
        self.assertTrue(stop)
        self.assertIn('CI_BELOW_FLOOR', why)

    def test_undecided_keeps_running(self):
        # 0 passes in 50 cells: hi = sqrt(ln40)/100 ≈ .192 > .05 floor
        stop, why = sq.stop_decision(0, 50, 0.05, 0.05, 'below')
        self.assertFalse(stop)
        self.assertTrue(why.startswith('UNDECIDED'), why)

    def test_decisively_above_stops(self):
        # 100/100 passes, alpha .05: hw = sqrt(ln40)/200 ≈ .1359
        # -> lo = .864 > .50 floor
        stop, why = sq.stop_decision(100, 100, 0.50, 0.05, 'above')
        self.assertTrue(stop)
        self.assertIn('CI_ABOVE_FLOOR', why)

    def test_coin_flip_never_separates_from_half(self):
        # p=0.5 vs floor 0.5: CI always contains the floor -> never stops
        for n in (5, 50, 500, 5000):
            stop, _ = sq.stop_decision(n // 2, n, 0.5, 0.05, 'below')
            self.assertFalse(stop, 'n=%d separated a coin flip?!' % n)

    def test_n_zero_and_side_guards(self):
        stop, why = sq.stop_decision(0, 0, 0.1, 0.05, 'below')
        self.assertFalse(stop)
        self.assertEqual(why, 'N_ZERO')
        with self.assertRaises(ValueError):
            sq.stop_decision(1, 1, 0.1, 0.05, 'sideways')


if __name__ == '__main__':
    unittest.main(verbosity=2)
