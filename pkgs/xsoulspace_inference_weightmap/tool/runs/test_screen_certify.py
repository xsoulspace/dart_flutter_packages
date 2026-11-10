#!/usr/bin/env python3
"""test_screen_certify.py - CPU-only pins for the L3 screen→certify core."""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import screen_certify as sc  # noqa: E402


class TestWinners(unittest.TestCase):
    def test_all_passing_in_frozen_order(self):
        rows = [('b', 5), ('a', 7), ('c', 0), ('d', 4)]
        self.assertEqual(sc.winners(rows, 4), ['b', 'a', 'd'])  # input order

    def test_never_select_best_only(self):
        rows = [('x', 9), ('y', 4)]
        self.assertEqual(sc.winners(rows, 4), ['x', 'y'])  # both, not top-1

    def test_floor_gate(self):
        self.assertEqual(sc.winners([('a', 3), ('b', 4)], 4), ['b'])


class TestConfusion(unittest.TestCase):
    def test_counts(self):
        c = sc.confusion([1, 1, 0, 0, 1, 0], [1, 0, 0, 0, 1, 1])
        self.assertEqual(c, {'tp': 2, 'fp': 1, 'tn': 2, 'fn': 1})

    def test_alignment_refuses(self):
        with self.assertRaises(ValueError):
            sc.confusion([1, 0], [1])


class TestROC(unittest.TestCase):
    def test_economics(self):
        conf = {'tp': 2, 'fp': 1, 'tn': 2, 'fn': 1}
        r = sc.screen_roc(conf, certified_run_n=3)
        self.assertEqual(r['screened_n'], 6)
        self.assertEqual(r['evals_skipped'], 3)
        self.assertEqual(r['evals_skipped_per_fn'], 3)
        self.assertAlmostEqual(r['tpr'], 2 / 3)
        self.assertAlmostEqual(r['fpr'], 1 / 3)

    def test_no_fn_is_infinite_economics(self):
        conf = {'tp': 2, 'fp': 0, 'tn': 4, 'fn': 0}
        r = sc.screen_roc(conf, certified_run_n=2)
        self.assertIsNone(r['evals_skipped_per_fn'])

    def test_degenerate_truth_named(self):
        # no true negatives at all -> fpr undefined, NAMED not invented
        conf = {'tp': 2, 'fp': 0, 'tn': 0, 'fn': 0}
        r = sc.screen_roc(conf, 2)
        self.assertTrue(r['degenerate_truth'])
        self.assertIsNone(r['fpr'])


class TestQueueAndAccounting(unittest.TestCase):
    def test_certify_queue_frozen_order(self):
        q = sc.certify_queue(['z', 'a', 'm'], ['a', 'm', 'z', 'other'])
        self.assertEqual(q, ['a', 'm', 'z'])          # frozen order
        self.assertEqual(sc.certify_queue(['new'], ['a', 'm']),
                         ['new'])                     # unknown sorts last

    def test_accounting_shape(self):
        rows = [('a', 5), ('b', 1), ('c', 4)]
        acc = sc.accounting(rows, floor=4, certified_run_n=2,
                            truth_flags=[True, False, True])
        self.assertEqual(acc['winners'], ['a', 'c'])
        self.assertEqual(acc['certify_queue'], ['a', 'c'])
        self.assertEqual(acc['confusion'], {'tp': 2, 'fp': 0, 'tn': 1,
                                            'fn': 0})
        self.assertEqual(acc['screen_quant'], '4bit')
        self.assertEqual(acc['cert_quant'], 'bf16')
        self.assertIn('never certify', acc['non_claim'])

    def test_resolution_none_never_downloads(self):
        self.assertIsNone(sc.resolve_model(['/nonexistent/a', None]))


if __name__ == '__main__':
    unittest.main(verbosity=2)
