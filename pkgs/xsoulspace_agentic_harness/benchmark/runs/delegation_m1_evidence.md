# Delegation M1 — first a2a dogfooding evidence (2026-09-02)

Driver: pi (deepseek via pi coding agent) delegating over process spawn to
`coding_agent.dart --json --backend open_router --runs 1 --json`.

## Row 1 — delegated_calc

- task sentence: "Implement lib/calc.dart so the test suite passes: provide int add(int a, int b) returning the sum of a and b."
- jail: seeded Dart package (pubspec + failing test/calc_test.dart); check = workspace convention `dart test` (D8/M0 — NO hardcoded checker)
- backend: open_router:deepseek/deepseek-v4-flash-0731 (pinned)
- verdict: **PASS** — decisions 11, tool rounds 15, tokens 15,725 (honest projection spend), wall 30.1s
- moves: list_dir×6 glob×2 read×4 write×2 run×1
- gate: `dart test exit=0`
- files: `delegation_m1_01_openrouter.ndjson` (PASS), `delegation_m1_01_pre_fix_FAIL.ndjson` (pre-fix)

## Bugs found by the FIRST delegation (the dogfooding payoff)

1. **Actor model id not router-resolvable (fixed).** The runner spawned the
   actor with a random `ModelId.create()`; the handler falls back to
   `Model(id: request.modelId)` whose name has no client builder →
   `initRuntime` throws → the actor NEVER generates. Measured: 3 verification
   attempts, 0 decisions, FAIL in ~2s. Fix: `actorModelId` param bound to a
   router-registered id; runner also keeps the host router (escalation reads
   the world's router; an empty resource silently degraded it).
2. **Empty `ModelRouterResource` overwrite (fixed).** `runCodingAgentOnce`
   replaced the host router with an empty one — agency capacity + escalation
   resolution silently degraded.

Both are integration seams invisible without a real end-to-end delegation —
the M1 shape earned its keep before Shape 2 started.
