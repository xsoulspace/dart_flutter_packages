#!/usr/bin/env python3
"""ws3_synthetic_validate.py - WS-3 scoring-core validation WITHOUT a model.

Builds a synthetic 24-layer activation tensor set (numpy) with a PLANTED
informative layer: loop prompts carry a direction that is visible in the
final-layer residual representation ONLY when that layer is unmasked (the
mask of layer l removes exactly layer l's MLP contribution, so masking the
planted layer makes the loop direction unpredictable from the remaining
layers). Then runs the SAME ridge/mask/scoring code path as the real tool
by importing ws3_masked_attribution as a module:
  - masked_final_from_contributions  (the mask arithmetic)
  - score_layers                     (ridge-on-neutral + error delta)
  - top_k_summary                    (k=3 ranking + chance line)

Tower model (two structural facts make the prior informative; both were
paid for in the 2026-11-05 design probes, see build_synthetic):
  1. NONLINEAR MASK REACTION: masking layer l does not merely subtract l's
     baseline contribution - downstream layers recompute around the hole.
     Modeled as gamma * ||c[l]||^2 * u_l added to the masked final
     representation. A purely linear synthetic makes every mask effect
     cancel exactly and the ranking degenerates to noise (probe: planted
     layer ranked 24/24).
  2. IN-SUBSPACE LOOP DIRECTION: the planted direction lives inside the
     planted layer's neutral activation subspace and nowhere else, so for
     l != planted the ridge passes the loop shift through in-distribution
     while for l == planted the masked-out column hides the shift's source
     and the reaction moves by ~gamma*amp^2 along u_planted - the WS-3
     signal. (Probe: a novel random direction outside the neutral span
     blew up kernel extrapolation at EVERY layer, margin only ~2x.)

Asserts: planted layer in top-3 AND named control layers out of top-3.
NOTE: among the 23 non-planted layers the scores are noise-level near
ties, so which layers take top-3 slots 2-3 is fixture luck; the --seed
values used by test/ws3_test.dart are FROZEN test vectors (deterministic
given a seed), not a statistical claim. The load-bearing assertion is the
planted layer's recovery with a large margin.
Prints one JSON object on stdout:
  {"synthetic_validated": true, "top3": [...], "planted_layer": ..., ...}

No model, no mlx, no Metal. Requires numpy (run under the wm-mlx venv
python: $HOME/.local/share/wm-mlx/bin/python).

Usage:
  $HOME/.local/share/wm-mlx/bin/python -I tool/runs/ws3_synthetic_validate.py \
      [--seed 20261105] [--planted-layer 17]

Exit codes (errors NAMED on stderr, never silent):
  0  synthetic_validated true (JSON printed)
  1  SYNTHETIC_ASSERTION_FAILED: the scoring core did not recover the
     planted layer (detail printed; this is a real failure of the prior
     machinery, recorded as a verdict, never patched away)
  2  NUMPY_UNAVAILABLE / MODULE_IMPORT_FAILED
"""

import argparse
import json
import os
import sys

EXIT_OK = 0
EXIT_INPUT = 1
EXIT_DEP_UNAVAILABLE = 2

N_LAYERS = 24          # pre-registered tower size (chance 3/24)
HIDDEN_DIM = 48
N_NEUTRAL = 48
N_LOOP = 16
LATENT_DIM = 12
PLANTED_AMP = 40.0     # loop-direction amplitude (per-vector norm). Frozen
                       # from the 2026-11-05 amplitude probe: the planted
                       # signal grows as amp^4 (reaction shift) while the
                       # non-planted ridge-extrapolation floor grows as
                       # amp^2, so the margin grows as amp^2: amp=20 ->
                       # ~2x (fragile), amp=40 -> 7-8x (frozen), amp=60 ->
                       # ~16x. At amp=40 both frozen seeds give identical
                       # top-3 membership and clean controls.
REACTION_GAMMA = 1.0   # nonlinear downstream reaction to a mask
NOISE_STD = 0.01
K_TOP = 3              # frozen (PREREG-D WS-3)
CONTROL_LAYERS = (0, 5, 11, 23)  # must stay OUT of top-3


def fail(code, detail, exit_code=EXIT_INPUT):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def import_scoring_core():
    """Import the real tool as a module (same-directory import)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import ws3_masked_attribution as ws3
    except ImportError as exc:
        print('MODULE_IMPORT_FAILED: ws3_masked_attribution (%s)' % exc,
              file=sys.stderr)
        sys.exit(EXIT_DEP_UNAVAILABLE)
    try:
        import numpy  # noqa: F401
    except ImportError as exc:
        print('NUMPY_UNAVAILABLE: %s (run under the wm-mlx venv python)'
              % exc, file=sys.stderr)
        sys.exit(EXIT_DEP_UNAVAILABLE)
    return ws3


def build_synthetic(ws3, np, seed, planted_layer):
    """Synthetic 24-layer activation set with one planted informative layer.

    Model of the tower: final residual = base + sum of per-layer MLP
    contributions c[p][k]; masking layer l removes exactly c[p][l] (the
    shared mask arithmetic from the real tool) AND adds a nonlinear
    downstream reaction gamma * ||c[p][l]||^2 * u_l, standing in for the
    recomputation of every layer downstream of the hole (without it the
    synthetic is exactly linear and the ranking degenerates to noise).
    Loop prompts carry amp*v inside the planted layer's contribution ONLY
    (v inside that layer's neutral activation subspace), so:
      - masking l != planted: the loop shift stays in-distribution for the
        ridge (column planted is still a feature; the shift lies in its
        neutral span) -> prediction tracks it -> error delta ~ noise floor;
      - masking l == planted: column planted is excluded from features, so
        nothing carries the shift, and the reaction moves by ~gamma*amp^2
        along u_planted, a direction no remaining feature carries ->
        large loop-vs-neutral error delta -> planted must rank top.
    """
    rng = np.random.default_rng(seed)
    n_prompts = N_NEUTRAL + N_LOOP
    latent = rng.normal(size=(n_prompts, LATENT_DIM))
    proj = rng.normal(size=(N_LAYERS, HIDDEN_DIM, LATENT_DIM)) \
        / np.sqrt(LATENT_DIM)
    # contributions: (n_prompts, N_LAYERS, HIDDEN_DIM), per-element ~N(0,1)
    contribs = np.einsum('pr,ldr->pld', latent, proj)
    contribs += rng.normal(scale=NOISE_STD, size=contribs.shape)

    # planted direction: INSIDE the planted layer's neutral activation
    # subspace (v = A_planted @ w0), present in that layer ONLY - visible
    # in the baseline features just where the mask will remove it. A novel
    # random v outside the neutral span was probed 2026-11-05 and rejected:
    # it blows up kernel-ridge extrapolation at EVERY layer (non-planted
    # err_loop 500-3000 vs planted 6171, margin only ~2x).
    w0 = rng.normal(size=LATENT_DIM)
    direction = proj[planted_layer] @ w0
    direction /= np.linalg.norm(direction)
    loop_idx = np.arange(N_NEUTRAL, n_prompts)
    contribs[loop_idx[:, None], planted_layer, :] \
        += PLANTED_AMP * direction[None, :]

    # per-layer reaction directions (unit), invisible across layers
    reaction_dirs = rng.normal(size=(N_LAYERS, HIDDEN_DIM))
    reaction_dirs /= np.linalg.norm(reaction_dirs, axis=1, keepdims=True)

    base = rng.normal(size=HIDDEN_DIM)
    targets = np.zeros((N_LAYERS, n_prompts, HIDDEN_DIM))
    for l in range(N_LAYERS):
        for p in range(n_prompts):
            reaction = REACTION_GAMMA \
                * float(np.dot(contribs[p, l], contribs[p, l])) \
                * reaction_dirs[l]
            targets[l, p] = ws3.masked_final_from_contributions(
                contribs[p], l, base) + reaction
        targets[l] += rng.normal(scale=NOISE_STD, size=targets[l].shape)

    features = contribs  # baseline (unmasked) per-layer MLP outputs
    return features, targets


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--seed', type=int, default=20261105)
    ap.add_argument('--planted-layer', type=int, default=17)
    args = ap.parse_args(argv)

    ws3 = import_scoring_core()
    import numpy as np

    if not 0 <= args.planted_layer < N_LAYERS:
        return fail('SYNTHETIC_ASSERTION_FAILED',
                    'planted layer %d out of range 0..%d'
                    % (args.planted_layer, N_LAYERS - 1))
    if args.planted_layer in CONTROL_LAYERS:
        return fail('SYNTHETIC_ASSERTION_FAILED',
                    'planted layer %d collides with a control layer'
                    % args.planted_layer)

    features, targets = build_synthetic(ws3, np, args.seed,
                                        args.planted_layer)
    records = ws3.score_layers(features, targets, N_NEUTRAL)
    summary = ws3.top_k_summary(records, K_TOP)

    top3 = [entry['layer'] for entry in summary['top_k']]
    planted_rec = next(r for r in records if r['layer'] == args.planted_layer)
    controls_in_top3 = [l for l in CONTROL_LAYERS if l in top3]
    max_other = max(r['score'] for r in records
                    if r['layer'] != args.planted_layer)

    problems = []
    if args.planted_layer not in top3:
        problems.append('planted layer %d not in top3 %s (rank %d, score '
                        '%.6g)' % (args.planted_layer, top3,
                                   planted_rec['rank'], planted_rec['score']))
    if controls_in_top3:
        problems.append('control layers leaked into top3: %s'
                        % controls_in_top3)
    if problems:
        return fail('SYNTHETIC_ASSERTION_FAILED', '; '.join(problems))

    result = {
        'synthetic_validated': True,
        'top3': top3,
        'planted_layer': args.planted_layer,
        'planted_rank': planted_rec['rank'],
        'planted_score': planted_rec['score'],
        'max_other_score': max_other,
        'separation_margin': (planted_rec['score'] / max_other)
                             if max_other else None,
        'runner_up': summary['top_k'][1] if len(summary['top_k']) > 1 else None,
        'k': K_TOP,
        'n_layers': N_LAYERS,
        'chance_preregistered': ws3.CHANCE_PREREGISTERED,
        'chance_top_k': summary['chance_top_k'],
        'ridge_lambda': ws3.RIDGE_LAMBDA,
        'control_layers_checked': list(CONTROL_LAYERS),
        'seed': args.seed,
        'n_neutral': N_NEUTRAL,
        'n_loop': N_LOOP,
        'scoring_core': 'imported from ws3_masked_attribution.py '
                        '(same ridge/mask/scoring code path as real runs)',
        'model_used': None,
    }
    print(json.dumps(result, indent=2))
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
