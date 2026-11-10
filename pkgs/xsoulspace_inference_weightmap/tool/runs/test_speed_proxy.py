#!/usr/bin/env python3
"""test_speed_proxy.py - CPU-only pins for the L1 loop-proxy policy
(PREREG-SPEED L1; golden-free, hand-computed expectations)."""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import speed_proxy as sp  # noqa: E402


class TestProxyStop(unittest.TestCase):
    def test_min_tokens_gate(self):
        # 3 fires recorded but only 200 tokens generated -> never stop
        self.assertFalse(sp.proxy_stop_decision(200, 3))

    def test_fires_short_of_threshold(self):
        self.assertFalse(sp.proxy_stop_decision(300, 2))

    def test_stops_at_policy_point(self):
        self.assertTrue(sp.proxy_stop_decision(256, 3))
        self.assertTrue(sp.proxy_stop_decision(1024, 5))

    def test_count_within_proxy_bounds(self):
        t = [10, 200, 900, 1100, 2000]
        self.assertEqual(sp.count_within_proxy(t, 3000), 3)  # bound 1024
        # generated_len 950 shrinks the bound to 950 — 900 still counts
        self.assertEqual(sp.count_within_proxy(t, 950), 3)
        self.assertEqual(sp.count_within_proxy(t, 850), 2)   # 900 now out


class TestClassify(unittest.TestCase):
    def test_loop_proxy_accepted_with_recorded_stop(self):
        self.assertEqual(sp.classify_row(None, 'proxy', 300, 4096,
                                         proxy_stop_at=300),
                         sp.LOOP_PROXY)

    def test_proxy_without_stop_point_refuses(self):
        with self.assertRaises(ValueError):
            sp.classify_row(None, 'proxy', 300, 4096)

    def test_proxy_out_of_policy_refuses(self):
        with self.assertRaises(ValueError):
            sp.classify_row(None, 'proxy', 100, 4096, proxy_stop_at=100)
        with self.assertRaises(ValueError):
            sp.classify_row(None, 'proxy', 2000, 4096, proxy_stop_at=2000)

    def test_eos_cap_truncated(self):
        self.assertEqual(sp.classify_row(None, 'eos', 50, 4096), sp.EOS)
        self.assertEqual(sp.classify_row(None, 'length', 4096, 4096),
                         sp.LOOP_CAP)
        self.assertEqual(sp.classify_row(None, 'truncated', 1500, 4096),
                         sp.TRUNCATED)

    def test_length_mismatch_refuses(self):
        with self.assertRaises(ValueError):
            sp.classify_row(None, 'length', 100, 4096)

    def test_unknown_finish_refuses(self):
        with self.assertRaises(ValueError):
            sp.classify_row(None, 'weird', 10, 4096)


if __name__ == '__main__':
    unittest.main(verbosity=2)
