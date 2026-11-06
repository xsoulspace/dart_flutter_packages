#!/usr/bin/env python3
"""ws3_masked_attribution.py - WS-3 masked-component attribution prior.

PREREG-D WS-3 (FROZEN 2026-11-05): mask each of the N text-tower layers'
MLP output in turn at capture time; predict the masked representation from
the remaining layers with ridge regression trained on NEUTRAL prompts only
(ridge lambda pre-registered 1e-3, closed form); prior score(l) =
prediction-error delta on loop prompts vs neutral. k=3 pre-registered;
chance line 3/24. PROPOSE-ONLY law: this prior NEVER certifies; it only
ranks candidate layers.

PYTHON-BOUNDARY script (weightmap AGENTS.md). Real runs execute in the
machine venv  $HOME/.local/share/wm-mlx/bin/python  (override for tests:
env WM3_VENV_PYTHON). If invoked under another interpreter for a REAL run,
the script polls up to 10 min (env WM3_VENV_POLL_SECONDS) for the venv
python to appear and re-execs into it; on timeout it fails NAMED
VENV_MISSING. --dry-run never polls, never imports numpy/mlx, writes
nothing, and works with any python3.

Usage:
  $HOME/.local/share/wm-mlx/bin/python -I tool/runs/ws3_masked_attribution.py \
      --model <hf-snapshot-dir> \
      --neutral-prompts <file: one prompt per line> \
      --loop-prompts <file: one prompt per line> \
      --layers <N> --out <path.json> [--dry-run]

Real-run semantics (masking during PREFILL only; no sampling, no cache,
one direct forward per prompt => deterministic):
  1. Baseline pass (unmasked): each transformer layer's MLP is wrapped in a
     recording shim; per prompt the token-mean-pooled MLP OUTPUT of every
     layer is captured -> features (n_prompts, N, d).
  2. Mask passes: for each layer l in 0..N-1 the shim of layer l returns
     mx.zeros_like(x) INSTEAD of the MLP output (the residual h is kept, so
     exactly layer l's MLP contribution is removed); a shim on the tower's
     final RMSNorm records its INPUT (the final-layer residual stream),
     token-mean-pooled -> masked target t[l][prompt].
  3. Scoring: for each l, ridge (closed form, lambda=1e-3, train-mean
     centered, dual form when n_train <= d) trained on NEUTRAL prompts
     predicts t[l] from the baseline features of the REMAINING layers
     (all k != l). score(l) = mean per-prompt MSE(loop) - mean MSE(neutral).
  4. Artifacts: --out summary JSON + sidecar <out stem>.per_layer.jsonl
     (one record per layer: score, errors, rank, per-prompt errors).

Hook point (discovered at runtime; NAMED HOOK_POINT_MISSING if absent):
  mlx.nn.Module has NO forward-hook API (mlx 0.32.x), so the mechanism is
  monkeypatching - the same shim idiom as the frozen capture_activations.py.
  qwen3 (mlx_lm/models/qwen3.py): Model.model -> Qwen3Model with .layers[i]
  (TransformerBlock: `r = self.mlp(self.post_attention_layernorm(h));
  out = h + r`) and .norm (RMSNorm on the final residual).
  qwen3_5 (mlx_lm/models/qwen3_5.py): Model.model is a property ->
  Qwen3_5TextModel (.layers[i].mlp is MLP or SparseMoeBlock, .norm RMSNorm);
  fallback path Model.language_model.model is also tried.

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or real run artifacts written)
  1  named input/runtime error:
       LAYERS_INVALID            --layers is not an int >= 2
       PROMPTS_FILE_UNREADABLE   a prompts file is missing/unreadable
       PROMPTS_EMPTY             a prompts file has no non-empty lines
       PROMPT_ENCODE_EMPTY       tokenizer produced no tokens for a prompt
       MODEL_DIR_MISSING         --model directory does not exist
       ARCH_SHAPE_UNEXPECTED     tower has fewer than --layers N layers
       HOOK_POINT_MISSING        text tower / layers[i].mlp / .norm not found
       OUT_UNWRITABLE            --out or the sidecar cannot be written
       SYNTHETIC_ASSERTION_FAILED (validator sibling; not raised here)
  2  named dependency unavailable (real run only):
       VENV_MISSING              venv python absent after the poll window
       NUMPY_UNAVAILABLE         numpy not importable in the venv
       MLX_UNAVAILABLE           mlx / mlx.nn / mlx_lm not importable
"""

import argparse
import json
import os
import sys
import time

EXIT_OK = 0
EXIT_INPUT = 1
EXIT_DEP_UNAVAILABLE = 2

# --- pre-registered constants (PREREG-D WS-3, FROZEN; do not parameterize) ---
RIDGE_LAMBDA = 1e-3
K_TOP = 3
CHANCE_PREREGISTERED = '3/24'

VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')
VENV_POLL_SECONDS_DEFAULT = 600  # house law: poll 10 min, then NAMED
VENV_POLL_INTERVAL = 5.0


def _venv_python():
    return os.environ.get('WM3_VENV_PYTHON', VENV_PYTHON_DEFAULT)


def _venv_poll_seconds():
    raw = os.environ.get('WM3_VENV_POLL_SECONDS')
    if raw is None:
        return VENV_POLL_SECONDS_DEFAULT
    try:
        return max(0.0, float(raw))
    except ValueError:
        return VENV_POLL_SECONDS_DEFAULT


def fail(code, detail, exit_code=EXIT_INPUT):
    """Print a NAMED error to stderr; return the exit code for main."""
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def read_prompts(path, which):
    """One prompt per line; blank lines ignored. Named RuntimeError on failure."""
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            lines = fh.read().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError('PROMPTS_FILE_UNREADABLE: %s prompts file %s (%s)'
                           % (which, path, exc))
    prompts = [ln.strip() for ln in lines if ln.strip()]
    if not prompts:
        raise RuntimeError('PROMPTS_EMPTY: %s prompts file %s has no '
                           'non-empty lines' % (which, path))
    return prompts


# --------------------------------------------------------------------------
# Scoring core (numpy imported lazily so this module stays importable, and
# --dry-run stays runnable, with stdlib only). ws3_synthetic_validate.py
# imports THESE functions so both paths share one ridge/mask/scoring core.
# --------------------------------------------------------------------------

def ridge_predict_multi(x_train, y_train, x_all, lam=RIDGE_LAMBDA):
    """Closed-form ridge regression, multi-output, train-mean centered.

    x_train: (n, d) features; y_train: (n, o) targets; x_all: (m, d).
    Uses the dual (kernel) form when n <= d, else the primal normal
    equations. lambda is the pre-registered 1e-3 by default.
    Returns predictions for x_all, shape (m, o).
    """
    import numpy as np

    mu_x = x_train.mean(axis=0)
    mu_y = y_train.mean(axis=0)
    xc = x_train - mu_x
    yc = y_train - mu_y
    n, d = xc.shape
    xa = x_all - mu_x
    if n <= d:
        gram = xc @ xc.T + lam * np.eye(n)
        alpha = np.linalg.solve(gram, yc)          # (n, o)
        pred = xa @ (xc.T @ alpha)
    else:
        w = np.linalg.solve(xc.T @ xc + lam * np.eye(d), xc.T @ yc)
        pred = xa @ w
    return pred + mu_y


def per_prompt_mse(y_true, y_pred):
    """Mean squared error per prompt (averaged over representation dims)."""
    import numpy as np

    return ((np.asarray(y_true) - np.asarray(y_pred)) ** 2).mean(axis=-1)


def masked_final_from_contributions(contributions, mask_layer, base):
    """The mask arithmetic, shared with the synthetic validator.

    final = base + sum of per-layer MLP contributions EXCEPT mask_layer.
    In the real path this arithmetic is performed by the model itself: the
    zeroing shim removes layer `mask_layer`'s MLP output from the residual
    stream and every downstream layer recomputes around the hole.
    """
    import numpy as np

    total = np.array(base, dtype=float, copy=True)
    for k, c in enumerate(contributions):
        if k != mask_layer:
            total = total + c
    return total


def score_layers(features, targets, n_neutral, lam=RIDGE_LAMBDA):
    """WS-3 prior scores for every masked layer.

    features: (n_prompts, L, d) baseline (unmasked) token-mean-pooled MLP
              outputs, one vector per layer per prompt.
    targets:  (L, n_prompts, d) final-layer residual representations
              (token-mean-pooled) captured with layer l's MLP zeroed.
    neutral prompts are the FIRST n_neutral rows; the rest are loop prompts.

    Returns one record per layer:
      {layer, score, mean_err_neutral, mean_err_loop, err_neutral, err_loop}
    score(l) = mean_err_loop - mean_err_neutral  (pre-registered delta).
    """
    import numpy as np

    features = np.asarray(features, dtype=float)
    targets = np.asarray(targets, dtype=float)
    n_prompts, n_layers, _d = features.shape
    if targets.shape[0] != n_layers or targets.shape[1] != n_prompts:
        raise ValueError('shape mismatch: features %r vs targets %r'
                         % (features.shape, targets.shape))
    records = []
    for l in range(n_layers):
        keep = [k for k in range(n_layers) if k != l]
        x_all = features[:, keep, :].reshape(n_prompts, -1)
        y_all = targets[l]
        pred = ridge_predict_multi(x_all[:n_neutral], y_all[:n_neutral],
                                   x_all, lam)
        err = per_prompt_mse(y_all, pred)
        err_neutral = err[:n_neutral]
        err_loop = err[n_neutral:]
        records.append({
            'layer': l,
            'score': float(err_loop.mean() - err_neutral.mean()),
            'mean_err_neutral': float(err_neutral.mean()),
            'mean_err_loop': float(err_loop.mean()),
            'err_neutral': [float(e) for e in err_neutral],
            'err_loop': [float(e) for e in err_loop],
        })
    return records


def top_k_summary(records, k=K_TOP):
    """Rank layers by score (desc; ties -> lower layer index), take top-k.

    Returns {'top_k': [{layer, score, rank}], 'chance_top_k': k/L,
             'scores_by_layer': [...]}. chance_top_k is the frozen chance
    line generalized to L layers (3/24 for the pre-registered tower).
    """
    n_layers = len(records)
    order = sorted(records, key=lambda r: (-r['score'], r['layer']))
    for rank, rec in enumerate(order, start=1):
        rec['rank'] = rank
    top = [{'layer': r['layer'], 'score': r['score'], 'rank': r['rank']}
           for r in order[:k]]
    return {
        'top_k': top,
        'k': k,
        'chance_top_k': (k / n_layers) if n_layers else None,
        'scores_by_layer': [r['score'] for r in records],
    }


# --------------------------------------------------------------------------
# Real-run machinery (mlx). Everything below runs only after the venv gate
# and the runtime numpy/mlx imports.
# --------------------------------------------------------------------------

def ensure_venv_python(argv):
    """Real-run venv gate: poll for the venv python, re-exec into it.

    Returns None when running under the venv python already; otherwise
    re-execs (never returns) or returns exit code 2 with NAMED VENV_MISSING
    when the venv python does not appear within the poll window.
    """
    venv_py = _venv_python()
    if os.path.realpath(sys.executable) == os.path.realpath(venv_py):
        return None
    deadline = time.monotonic() + _venv_poll_seconds()
    announced = False
    while True:
        if os.path.isfile(venv_py) and os.access(venv_py, os.X_OK):
            os.execv(venv_py, [venv_py, '-I', os.path.abspath(__file__)]
                     + list(argv))
        if time.monotonic() >= deadline:
            return fail(
                'VENV_MISSING',
                'venv python %s not found/executable after %.0fs poll '
                '(real runs require the wm-mlx venv; --dry-run does not)'
                % (venv_py, _venv_poll_seconds()),
                EXIT_DEP_UNAVAILABLE)
        if not announced:
            print('waiting for venv python %s (poll window %.0fs)...'
                  % (venv_py, _venv_poll_seconds()), file=sys.stderr)
            announced = True
        time.sleep(VENV_POLL_INTERVAL)


class HookPointMissing(RuntimeError):
    """Raised when the mask/record hook point cannot be found (NAMED)."""


def discover_text_tower(model):
    """Find the text tower exposing .layers and .norm.

    Tries, in order: model.model (qwen3 Qwen3Model; qwen3_5 Model.model
    property -> Qwen3_5TextModel), then model.language_model.model.
    Returns (tower, path_name). Raises HookPointMissing otherwise.
    """
    candidates = (
        ('model', lambda m: m.model),
        ('language_model.model', lambda m: m.language_model.model),
    )
    tried = []
    for name, getter in candidates:
        try:
            tower = getter(model)
        except AttributeError:
            tried.append('%s: attribute absent' % name)
            continue
        if getattr(tower, 'layers', None) is not None \
                and getattr(tower, 'norm', None) is not None:
            return tower, name
        tried.append('%s: found %s but it lacks .layers/.norm'
                     % (name, type(tower).__name__))
    raise HookPointMissing(
        'no text tower with .layers/.norm on %s (tried: %s)'
        % (type(model).__name__, '; '.join(tried)))


def install_shims(module_cls, mx, tower, n_layers):
    """Monkeypatch recording/zeroing MLP shims + a final-norm recorder.

    module_cls is mlx.nn.Module (the shim base class).
    Returns (mlp_shims, norm_recorder). Raises HookPointMissing when a
    layer lacks .mlp or the norm tap is missing; RuntimeError
    (ARCH_SHAPE_UNEXPECTED) when the tower is shorter than --layers.
    """

    class MlpShim(module_cls):
        """Records the token-mean-pooled MLP output; optionally zeroes it.

        Zeroing returns mx.zeros_like(x) WITHOUT computing the inner MLP:
        `out = h + r` in the transformer block then contributes exactly
        nothing for this layer (its MLP output is masked).
        """

        def __init__(self, inner, layer_index):
            super().__init__()
            self.inner = inner
            self.layer_index = layer_index
            self.zero_output = False
            self.sink = None  # list; when set, record mean-pooled output

        def __call__(self, x, *rest, **kw):
            if self.zero_output:
                return mx.zeros_like(x)
            y = self.inner(x, *rest, **kw)
            if self.sink is not None:
                flat = y.reshape(-1, y.shape[-1])
                self.sink.append(flat.mean(axis=0))
            return y

    class NormRecorder(module_cls):
        """Records the norm INPUT: the final-layer residual stream."""

        def __init__(self, inner):
            super().__init__()
            self.inner = inner
            self.recording = False
            self.records = []

        def __call__(self, x, *rest, **kw):
            if self.recording:
                flat = x.reshape(-1, x.shape[-1])
                self.records.append(flat.mean(axis=0))
            return self.inner(x, *rest, **kw)

    layers = tower.layers
    if len(layers) < n_layers:
        raise RuntimeError(
            'ARCH_SHAPE_UNEXPECTED: tower %s has %d layers; --layers '
            'requested %d' % (type(tower).__name__, len(layers), n_layers))
    mlp_shims = []
    for i in range(n_layers):
        layer = layers[i]
        if getattr(layer, 'mlp', None) is None:
            raise HookPointMissing('layer %d (%s) has no .mlp attribute'
                                   % (i, type(layer).__name__))
        shim = MlpShim(layer.mlp, i)
        layer.mlp = shim
        mlp_shims.append(shim)
    if getattr(tower, 'norm', None) is None:
        raise HookPointMissing('tower %s has no .norm (final RMSNorm tap)'
                               % type(tower).__name__)
    recorder = NormRecorder(tower.norm)
    tower.norm = recorder
    return mlp_shims, recorder


def _to_np(mx, arr):
    import numpy as np

    mx.eval(arr)
    return np.array(arr.tolist(), dtype=float)


def _forward_prefill(mx, model, tokenizer, prompt, record_flag_setter):
    """One deterministic prefill forward (no sampling, no cache)."""
    ids = tokenizer.encode(prompt)
    if not ids:
        raise RuntimeError('PROMPT_ENCODE_EMPTY: %r' % prompt)
    record_flag_setter()
    model(mx.array([ids]))


def capture_real(model, mx, nn, tokenizer, prompts_neutral,
                 prompts_loop, n_layers):
    """Baseline + per-layer masked prefills -> (features, targets).

    features: np (n_prompts, n_layers, d) baseline MLP outputs.
    targets:  np (n_layers, n_prompts, d) masked final residual reps.
    prompts are ordered neutral-first, then loop (score_layers contract).
    """
    import numpy as np

    tower, _ = discover_text_tower(model)
    mlp_shims, norm_rec = install_shims(nn.Module, mx, tower, n_layers)

    prompts = list(prompts_neutral) + list(prompts_loop)
    n_prompts = len(prompts)

    def arm_recording():
        for sh in mlp_shims:
            sh.sink = []
        norm_rec.records = []
        norm_rec.recording = True

    def disarm_recording():
        norm_rec.recording = False

    # --- baseline pass (unmasked): per-layer MLP outputs ---
    features = None
    for p_i, prompt in enumerate(prompts):
        _forward_prefill(mx, model, tokenizer, prompt, arm_recording)
        disarm_recording()
        if len(norm_rec.records) != 1:
            raise RuntimeError('ARCH_SHAPE_UNEXPECTED: norm tapped %d times '
                               'in one prefill' % len(norm_rec.records))
        row = [_to_np(mx, sh.sink[0]) for sh in mlp_shims]
        stacked = np.stack(row)  # (n_layers, d)
        if features is None:
            features = np.zeros((n_prompts, n_layers, stacked.shape[1]))
        features[p_i] = stacked

    # --- mask passes: one per layer ---
    d = features.shape[2]
    targets = np.zeros((n_layers, n_prompts, d))
    for l in range(n_layers):
        mlp_shims[l].zero_output = True
        try:
            for p_i, prompt in enumerate(prompts):
                _forward_prefill(mx, model, tokenizer, prompt, arm_recording)
                disarm_recording()
                if len(norm_rec.records) != 1:
                    raise RuntimeError(
                        'ARCH_SHAPE_UNEXPECTED: norm tapped %d times in one '
                        'prefill' % len(norm_rec.records))
                targets[l, p_i] = _to_np(mx, norm_rec.records[0])
        finally:
            mlp_shims[l].zero_output = False
    return features, targets


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True,
                    help='model dir (HF hub snapshot layout)')
    ap.add_argument('--neutral-prompts', required=True,
                    help='neutral prompts file, one prompt per line')
    ap.add_argument('--loop-prompts', required=True,
                    help='loop prompts file, one prompt per line')
    ap.add_argument('--layers', required=True,
                    help='N: mask each text-tower layer 0..N-1 in turn')
    ap.add_argument('--out', required=True, help='summary JSON path')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the plan and exit 0 WITHOUT venv poll or '
                         'numpy/mlx imports')
    args = ap.parse_args(argv)

    try:
        n_layers = int(args.layers)
        if n_layers < 2:
            raise ValueError('must be >= 2')
    except ValueError as exc:
        return fail('LAYERS_INVALID', '%r (%s)' % (args.layers, exc))

    try:
        prompts_neutral = read_prompts(args.neutral_prompts, 'neutral')
        prompts_loop = read_prompts(args.loop_prompts, 'loop')
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT

    if args.dry_run:
        plan = {
            'mode': 'dry-run',
            'arm': 'WS-3 masked-component attribution prior (PREREG-D, '
                   'frozen; propose-only)',
            'model': args.model,
            'layers': n_layers,
            'layers_masked': list(range(n_layers)),
            'neutral_prompt_count': len(prompts_neutral),
            'loop_prompt_count': len(prompts_loop),
            'ridge_lambda': RIDGE_LAMBDA,
            'k_top': K_TOP,
            'chance_preregistered': CHANCE_PREREGISTERED,
            'prefills_planned': (n_layers + 1)
                                * (len(prompts_neutral) + len(prompts_loop)),
            'out': args.out,
            'per_layer_jsonl': sidecar_path(args.out),
            'mlx_imported': False,
            'numpy_imported': False,
            'venv_polled': False,
            'note': 'plan only; no venv poll; numpy/mlx NOT imported; '
                    'nothing written',
        }
        print(json.dumps(plan, indent=2))
        return EXIT_OK

    # --- real run: venv gate FIRST (polls; re-execs; or NAMED VENV_MISSING) ---
    venv_rc = ensure_venv_python(argv)
    if venv_rc is not None:
        return venv_rc

    try:
        import numpy  # noqa: F401
    except ImportError as exc:
        return fail('NUMPY_UNAVAILABLE', str(exc), EXIT_DEP_UNAVAILABLE)
    try:
        import mlx.core as mx
        import mlx.nn as nn
        from mlx_lm import load
    except ImportError as exc:
        return fail('MLX_UNAVAILABLE', '%s (real runs need the wm-mlx venv; '
                                       '--dry-run does not)' % exc,
                    EXIT_DEP_UNAVAILABLE)

    if not os.path.isdir(args.model):
        return fail('MODEL_DIR_MISSING', args.model)

    model, tokenizer = load(args.model)
    try:
        tower, tower_path = discover_text_tower(model)
    except HookPointMissing as exc:
        return fail('HOOK_POINT_MISSING', str(exc))
    try:
        features, targets = capture_real(
            model, mx, nn, tokenizer,
            prompts_neutral, prompts_loop, n_layers)
    except HookPointMissing as exc:
        return fail('HOOK_POINT_MISSING', str(exc))
    except RuntimeError as exc:
        msg = str(exc)
        code = msg.split(':', 1)[0] if msg.split(':', 1)[0].isupper() \
            else 'ARCH_SHAPE_UNEXPECTED'
        return fail(code, msg)

    records = score_layers(features, targets, len(prompts_neutral))
    summary = top_k_summary(records, K_TOP)

    hook_report = {
        'mechanism': 'monkeypatch shims (mlx.nn.Module has no forward-hook '
                     'API in mlx 0.32.x); same idiom as the frozen '
                     'capture_activations.py',
        'tower_path': tower_path,
        'tower_class': type(tower).__name__,
        'mask_point': '%s.layers[i].mlp -> shim returning mx.zeros_like(x)'
                      % tower_path,
        'final_representation_tap': '%s.norm input (final-layer residual '
                                    'stream), token-mean-pooled per prompt'
                                    % tower_path,
        'forward': 'direct single prefill forward per prompt (no sampling, '
                   'no cache; deterministic)',
    }

    sidecar = sidecar_path(args.out)
    try:
        out_abs = os.path.abspath(args.out)
        side_abs = os.path.abspath(sidecar)
        os.makedirs(os.path.dirname(out_abs), exist_ok=True)
        os.makedirs(os.path.dirname(side_abs), exist_ok=True)
        with open(side_abs, 'w', encoding='utf-8') as fh:
            for rec in sorted(records, key=lambda r: r['layer']):
                fh.write(json.dumps(rec) + '\n')
        artifact = {
            'tool': 'ws3_masked_attribution.py',
            'arm': 'WS-3 masked-component attribution prior (PREREG-D, '
                   'frozen)',
            'propose_only': True,
            'law': 'the prior NEVER certifies; it only ranks candidates',
            'model': args.model,
            'layers_masked': n_layers,
            'neutral_prompt_count': len(prompts_neutral),
            'loop_prompt_count': len(prompts_loop),
            'ridge_lambda': RIDGE_LAMBDA,
            'k_top': K_TOP,
            'chance_preregistered': CHANCE_PREREGISTERED,
            'chance_top_k': summary['chance_top_k'],
            'hook_point': hook_report,
            'top_k': summary['top_k'],
            'scores_by_layer': summary['scores_by_layer'],
            'per_layer_jsonl': side_abs,
            'out_files': [out_abs, side_abs],
        }
        with open(out_abs, 'w', encoding='utf-8') as fh:
            json.dump(artifact, fh, indent=2)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('wrote %s (+ %s)' % (out_abs, side_abs))
    return EXIT_OK


def sidecar_path(out_path):
    stem, ext = os.path.splitext(out_path)
    return stem + '.per_layer.jsonl'


if __name__ == '__main__':
    sys.exit(main())
