#!/usr/bin/env python3
"""capture_activations.py - Phase-A per-layer mean activation capture.

PYTHON-BOUNDARY script (weightmap AGENTS.md): while this package lives,
Phase-A activation capture runs in Python against the mlx runtime; NATIVE
capture in the engine requires an ADR in the owning package (mlx_native),
never here. At real-run scale this tool is PHASE-A-ONLY: it records per-layer
mean hidden activations (shape info + values as lists) into one JSON artifact.

Usage:
  python3 -I tool/eval/capture_activations.py \
      --model <hf-snapshot-dir> --prompts <file: one prompt per line> \
      --layers <spec, e.g. "15,19" or "0-3,15"> --out <path.json> [--dry-run]

--dry-run prints the plan (model, layer list, prompt count) as JSON on stdout
and exits 0 WITHOUT importing mlx. Nothing is written.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or real capture written)
  1  named input/runtime error:
       LAYER_SPEC_INVALID      --layers is not ints/ranges ("15,19", "0-3,15")
       PROMPTS_FILE_UNREADABLE prompts file missing/unreadable/undecodable
       PROMPTS_EMPTY           prompts file has no non-empty lines
       MODEL_DIR_MISSING       --model directory does not exist (real run)
       ARCH_SHAPE_UNEXPECTED   model tree lacks .model.layers[i].mlp, or a
                               requested layer is out of range, or a capture
                               saw no tokens (real run)
       OUT_UNWRITABLE          --out path cannot be written (real run)
  2  named dependency unavailable (real run only; dry-run never imports mlx):
       MLX_UNAVAILABLE         mlx / mlx.nn / mlx_lm not importable

Real-run semantics: each selected transformer layer's MLP is wrapped in a
capturing shim; one greedy prefill per prompt (max_tokens=1) runs through the
model; the MLP INPUT activations are averaged over all tokens of all prompts.
The artifact is {"per_layer": {"<layer>": {"shape": [hidden],
"tokens_averaged": n, "mean_activation": [floats]}}}, plus plan provenance.
"""

import argparse
import json
import os
import sys

EXIT_OK = 0
EXIT_INPUT = 1
EXIT_DEP_UNAVAILABLE = 2


def fail(code, detail):
    """Print a NAMED error to stderr; return the exit code for main."""
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_INPUT


def parse_layer_spec(spec):
    """Parse '15,19' / '0-3,15' into a sorted unique int list.

    Raises ValueError (mapped to LAYER_SPEC_INVALID by main) on anything else.
    """
    layers = set()
    for part in spec.split(','):
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            lo_s, _, hi_s = part.partition('-')
            lo, hi = int(lo_s), int(hi_s)  # int() raises ValueError on junk
            if lo < 0 or hi < lo:
                raise ValueError('bad range %r' % part)
            layers.update(range(lo, hi + 1))
        else:
            n = int(part)
            if n < 0:
                raise ValueError('negative layer index %r' % part)
            layers.add(n)
    if not layers:
        raise ValueError('empty layer spec')
    return sorted(layers)


def read_prompts(path):
    """One prompt per line; blank lines ignored. Named RuntimeError on failure."""
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            lines = fh.read().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError('PROMPTS_FILE_UNREADABLE: %s (%s)' % (path, exc))
    prompts = [ln.strip() for ln in lines]
    prompts = [p for p in prompts if p]
    if not prompts:
        raise RuntimeError('PROMPTS_EMPTY: %s has no non-empty lines' % path)
    return prompts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True,
                    help='model dir (HF hub snapshot layout)')
    ap.add_argument('--prompts', required=True,
                    help='prompts file, one prompt per line')
    ap.add_argument('--layers', required=True,
                    help='layer spec: "15,19" or "0-3,15"')
    ap.add_argument('--out', required=True, help='output JSON path')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the plan and exit 0 WITHOUT importing mlx')
    args = ap.parse_args(argv)

    try:
        layers = parse_layer_spec(args.layers)
    except ValueError as exc:
        return fail('LAYER_SPEC_INVALID', '%r (%s)' % (args.layers, exc))

    try:
        prompts = read_prompts(args.prompts)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT

    if args.dry_run:
        plan = {
            'mode': 'dry-run',
            'model': args.model,
            'layers': layers,
            'prompt_count': len(prompts),
            'out': args.out,
            'mlx_imported': False,
            'note': 'plan only; mlx NOT imported; nothing written',
        }
        print(json.dumps(plan, indent=2))
        return EXIT_OK

    # --- real run: runtime imports (PYTHON-BOUNDARY idiom) ---
    try:
        import mlx.core as mx
        import mlx.nn as nn
        from mlx_lm import generate, load
    except ImportError as exc:
        print('MLX_UNAVAILABLE: %s' % exc, file=sys.stderr)
        print('(dry-run works without mlx; the real capture does not. '
              'Native capture requires an ADR in the owning package.)',
              file=sys.stderr)
        return EXIT_DEP_UNAVAILABLE

    if not os.path.isdir(args.model):
        return fail('MODEL_DIR_MISSING', args.model)

    model, tokenizer = load(args.model)
    transformer_layers = getattr(getattr(model, 'model', None), 'layers', None)
    if not transformer_layers:
        return fail('ARCH_SHAPE_UNEXPECTED', 'model tree has no .model.layers')
    out_of_range = [i for i in layers if i >= len(transformer_layers)]
    if out_of_range:
        return fail('ARCH_SHAPE_UNEXPECTED',
                    'model has %d layers; requested out-of-range %s'
                    % (len(transformer_layers), out_of_range))

    sums = {i: None for i in layers}
    counts = {i: 0 for i in layers}

    class _CaptureMlp(nn.Module):
        """Shim recording the MLP input activations of one layer."""

        def __init__(self, inner, layer_index):
            super().__init__()
            self.inner = inner
            self.layer_index = layer_index

        def __call__(self, x, *rest, **kw):
            flat = x.reshape(-1, x.shape[-1])
            colsum = flat.sum(axis=0)
            sums[self.layer_index] = (
                colsum if sums[self.layer_index] is None
                else sums[self.layer_index] + colsum
            )
            counts[self.layer_index] += flat.shape[0]
            return self.inner(x, *rest, **kw)

    for i in layers:
        layer = transformer_layers[i]
        if getattr(layer, 'mlp', None) is None:
            return fail('ARCH_SHAPE_UNEXPECTED', 'layer %d has no .mlp' % i)
        layer.mlp = _CaptureMlp(layer.mlp, i)

    for prompt in prompts:
        generate(model, tokenizer, prompt=prompt, max_tokens=1, verbose=False)

    per_layer = {}
    for i in layers:
        if counts[i] == 0:
            return fail('ARCH_SHAPE_UNEXPECTED',
                        'layer %d captured no tokens' % i)
        mean = sums[i] / counts[i]
        mx.eval(mean)
        per_layer[str(i)] = {
            'shape': list(mean.shape),
            'tokens_averaged': counts[i],
            'mean_activation': mean.tolist(),
        }

    artifact = {
        'tool': 'capture_activations.py',
        'phase': 'A (python boundary; native capture requires an ADR in the '
                 'owning package)',
        'model': args.model,
        'layers': layers,
        'prompt_count': len(prompts),
        'per_layer': per_layer,
    }
    try:
        out_abs = os.path.abspath(args.out)
        os.makedirs(os.path.dirname(out_abs), exist_ok=True)
        with open(out_abs, 'w', encoding='utf-8') as fh:
            json.dump(artifact, fh, indent=2)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('wrote %s' % out_abs)
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
