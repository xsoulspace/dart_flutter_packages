#!/usr/bin/env python3
"""test_delta_merge.py - CPU-only pins for the L4 reference merge (the
parity anchor for delta_sidecar.rs; hand-computed expectations)."""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import delta_merge as dm  # noqa: E402


class TestMergedColumn(unittest.TestCase):
    def test_hand_computed(self):
        base = [1.0, -2.0, 0.5]
        self.assertEqual(dm.merged_column(base, [10.0, 0.0, -4.0], 0.5),
                         [6.0, -2.0, -1.5])

    def test_rows_mismatch_refuses(self):
        with self.assertRaises(ValueError):
            dm.merged_column([1.0, 2.0], [1.0], 1.0)

    def test_base_never_mutated(self):
        base = [1.0, 2.0]
        dm.merged_column(base, [1.0, 1.0], 3.0)
        self.assertEqual(base, [1.0, 2.0])


BASE = [[1.0, 2.0, 3.0, 4.0],
        [5.0, 6.0, 7.0, 8.0]]


class TestMergedTensor(unittest.TestCase):
    def test_hand_computed_two_columns(self):
        # FROZEN semantics: EVERY chosen column j receives scale*direction
        # down its rows (direction indexed by ROW). direction [10, -10],
        # scale 0.5 (binary-exact). Row 0 uses direction[0]=+10: col0
        # 1+5=6, col2 3+5=8. Row 1 uses direction[1]=-10: col0 5-5=0,
        # col2 7-5=2. (Derived THIRD time after two wrong derivations —
        # exactly why goldens get re-derived at write time.)
        out = dm.merged_tensor(BASE, [0, 2], [10.0, -10.0], 0.5)
        self.assertEqual(out, [[6.0, 2.0, 8.0, 4.0],
                               [0.0, 6.0, 2.0, 8.0]])
        self.assertEqual(BASE[0][0], 1.0)   # base untouched

    def test_column_range_refuses(self):
        with self.assertRaises(ValueError):
            dm.merged_tensor(BASE, [4], [1.0, 1.0], 1.0)
        with self.assertRaises(ValueError):
            dm.merged_tensor(BASE, [-1], [1.0, 1.0], 1.0)

    def test_empty_base_refuses(self):
        with self.assertRaises(ValueError):
            dm.merged_tensor([], [0], [1.0], 1.0)

    def test_zero_scale_is_identity(self):
        out = dm.merged_tensor(BASE, [0, 1, 2, 3], [9.0, 9.0], 0.0)
        self.assertEqual(out, BASE)

    def test_direction_rows_mismatch_refuses(self):
        # the frozen tool checks direction-vs-rows; a silent-extra tolerance
        # would hide spec authoring errors (Rust twin refuses — parity law)
        with self.assertRaises(ValueError):
            dm.merged_tensor(BASE, [0], [9.0, 9.0, 9.0, 9.0], 0.0)


class TestDigest(unittest.TestCase):
    def test_digest_stable_and_sensitive(self):
        a = dm.merged_tensor(BASE, [0], [1.0, 1.0], 1.0)
        b = dm.merged_tensor(BASE, [0], [1.0, 1.0], 1.0)
        self.assertEqual(dm.spec_digest(a, 2, 4), dm.spec_digest(b, 2, 4))
        c = dm.merged_tensor(BASE, [0], [1.0, 2.0], 1.0)
        self.assertNotEqual(dm.spec_digest(a, 2, 4), dm.spec_digest(c, 2, 4))

    def test_f32_parity_digest_exact_and_sensitive(self):
        # L4 gate anchor: values rounded through binary32 before digesting
        # — the Rust twin (f32 arithmetic) must match byte-for-byte.
        a = dm.merged_tensor(BASE, [0], [1.0, 1.0], 1.0)
        b = dm.merged_tensor(BASE, [0], [1.0, 1.0], 1.0)
        self.assertEqual(dm.f32_parity_digest(a, 2, 4),
                         dm.f32_parity_digest(b, 2, 4))
        # an f32-ulp-level change IS visible (this is why %.6f cannot serve
        # for magnitudes >= ~8 where f32 ulp exceeds 1e-6): base 1.0 + dir
        # 1.0 vs 1.0 + 2^-16 differ at 2.0000153 — representable at f32
        # (ulp(2.0) ≈ 2.4e-7), unlike 1e8 + 1 which ROUNDS BACK to 1e8.
        x = dm.merged_tensor(BASE, [0], [1.0, 1.0], 1.0)
        y = dm.merged_tensor(BASE, [0], [1.0 + 2.0 ** -16, 1.0], 1.0)
        self.assertNotEqual(dm.f32_parity_digest(x, 2, 4),
                            dm.f32_parity_digest(y, 2, 4))
        self.assertNotEqual(dm.spec_digest(a, 2, 4),
                            dm.f32_parity_digest(a, 2, 4))


if __name__ == '__main__':
    unittest.main(verbosity=2)
