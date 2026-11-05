# xsoulspace_inference_weightmap

ISOLATED EXPERIMENT. Weight-space concept editing (the "weightmap") and its
validation program: planted-ground-truth error rates, control arms, blinding,
replication matrices, and paper-comparability arms against the MIT
weight-space-programming benchmarks.

- [PROGRAM.md](PROGRAM.md) — the complete plan (layers, phases, governance).
- [PREREG-A.md](PREREG-A.md) — Phase A preregistration (frozen floors, seeds, kill clauses).
- [VERDICTS.md](VERDICTS.md) — the append-only verdict ledger (the denominator lives here).
- [AGENTS.md](AGENTS.md) — package contract, isolation boundary, removal procedure.

Removal: delete this directory and its `pkgs/*` workspace entry resolves away;
no other package imports this one. Model weights live in the HF hub cache,
never in this tree.
