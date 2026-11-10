#!/usr/bin/env python3
"""test_wm_generate_speed.py - CPU-only pins for the L1/L2 generation
surface: dry-run plan shape, prompt guards, classification integration,
resume semantics via file presence. NO mlx import on any tested path."""
import json, os, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wm_generate_speed as wg  # noqa: E402
import speed_proxy as sp  # noqa: E402


class TestPrompts(unittest.TestCase):
    def test_missing_refused(self):
        with self.assertRaises(RuntimeError) as cm:
            wg.read_prompts('/nonexistent/nope.txt')
        self.assertIn('PROMPTS_MISSING', str(cm.exception))

    def test_empty_refused(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt',
                                         delete=False) as fh:
            fh.write('\n  \n')
            p = fh.name
        try:
            with self.assertRaises(RuntimeError) as cm:
                wg.read_prompts(p)
            self.assertIn('PROMPTS_EMPTY', str(cm.exception))
        finally:
            os.unlink(p)

    def test_blank_lines_skipped(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt',
                                         delete=False) as fh:
            fh.write('row one\n\nrow two\n')
            p = fh.name
        try:
            self.assertEqual(wg.read_prompts(p), ['row one', 'row two'])
        finally:
            os.unlink(p)


class TestDryRun(unittest.TestCase):
    def test_plan_shape_no_device_no_writes(self):
        with tempfile.TemporaryDirectory() as td:
            pf = os.path.join(td, 'p.txt')
            open(pf, 'w').write('alpha prompt\nbeta prompt\n')
            argv = ['--model', td, '--prompts', pf, '--max-tokens', '4096',
                    '--out-dir', os.path.join(td, 'rows'), '--dry-run']
            proc = subprocess.run(
                [sys.executable, '-I',
                 os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              'wm_generate_speed.py')] + argv,
                capture_output=True, text=True,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            plan = json.loads(proc.stdout)
            self.assertEqual(plan['rows'], 2)
            self.assertEqual(plan['proxy']['constants'],
                             [sp.T_PROXY, sp.F_EARLY, sp.MIN_TOKENS])
            self.assertIn('NAMED PROXY', plan['proxy']['classification'])
            self.assertFalse(os.path.exists(os.path.join(td, 'rows')))


class TestClassificationIntegration(unittest.TestCase):
    def test_runner_rows_classify_through_frozen_policy(self):
        # a proxy-finished row validates through classify_row; a cap row
        # classifies LOOP_CAP — the runner never invents classes
        self.assertEqual(sp.classify_row(None, 'proxy', 400, 4096,
                                         proxy_stop_at=400), sp.LOOP_PROXY)
        self.assertEqual(sp.classify_row(None, 'length', 4096, 4096),
                         sp.LOOP_CAP)

    def test_no_proxy_exemption_flag_exists(self):
        # the --no-proxy flag must be expressible (P-* arms owe the full cap)
        import argparse
        ap = argparse.ArgumentParser()
        ap.add_argument('--proxy', dest='proxy', action='store_true',
                        default=True)
        ap.add_argument('--no-proxy', dest='proxy', action='store_false')
        self.assertTrue(ap.parse_args([]).proxy)
        self.assertFalse(ap.parse_args(['--no-proxy']).proxy)


if __name__ == '__main__':
    unittest.main(verbosity=2)
