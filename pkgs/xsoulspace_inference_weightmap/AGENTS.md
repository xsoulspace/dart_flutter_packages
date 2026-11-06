# AGENTS.md — xsoulspace_inference_weightmap

## North star impact

`sub_star`. This package is an experimental child of the monorepo north star.
Boundary: it CANNOT override the repo north star, route package maintenance
through the harness, change any sibling package, or add engine-side surface to
`xsoulspace_inference_mlx_native`. Engine-side needs (e.g. native activation
capture) go through an ADR in the owning package, never through this one.
While this package lives, Phase A activation capture uses the Python boundary
scripts under `tool/eval/` (PYTHON-BOUNDARY law of mlx_native).

## Isolation and removal

- No sibling package depends on this one; it depends on `xsoulspace_inference_core` (vocabulary only).
- Removal = delete this directory. The Qwen3.5-0.8B cast entry in mlx_native is a
  SEPARATE, independently revertible change (standing switchability feature,
  not part of this experiment's removal scope).
- Weights, checkpoints, and deltas NEVER land in this tree or `.dart_tool`:
  HF hub cache for weights, `$TMPDIR` for scratch (probe scratch law),
  durable evidence is textual (receipts, ledgers, verdicts).

## Validation gate

- `dart test` in this package (from the monorepo root: `dart test pkgs/xsoulspace_inference_weightmap`).
- Python boundary scripts self-check with `--dry-run` and refuse with NAMED
  errors when a dependency is absent; tests that need them skip with a named
  reason, never silently.
- Frozen-oracle law: scoring and gate scripts under `tool/` are frozen once
  PREREG-A A4 lands; changing them requires a new prereg row, not an edit.
- Python runners (Dart Process.run or shell) MUST set
  PYTHONDONTWRITEBYTECODE=1: `__pycache__` in the repo tree violates the probe
  scratch law. Sweep on sight if a runner forgets.

## Claims and evidence

Every claim routes to VERDICTS.md (weakest true current status), PREREG-*.md
(frozen decision rules), or receipts (textual proof). No claim in prose without
a ledger row. Selective reporting is structurally impossible: the ledger holds
the denominator (every proposed direction, every run, every named failure).
