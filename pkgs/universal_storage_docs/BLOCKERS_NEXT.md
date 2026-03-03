# Universal Storage: Next Blockers

Last updated: `2026-03-03`

This is the only canonical next-steps document for Universal Storage.

## Blocking Items

1. Fix `last_answer/packages/core` full-suite failure:
   - Failing test: `test/data_sources/local/shared_preferences_db_test.dart`
   - Failure: type cast in prefs migration path (`String` vs `List<dynamic>`)
   - Exit condition: `flutter test` passes for `last_answer/packages/core`.

2. Remove analyzer **errors** in `prompt_character` app runtime/tests:
   - Current errors include `discarded_futures` and bootstrap test contract drift.
   - Exit condition: `flutter analyze --no-fatal-infos --no-fatal-warnings` exits 0
     for the required release scope.

3. Keep hard-cutover guarantees enforced in CI for all release targets:
   - Required sequence: path audit -> clone guard audit -> analyze (errors-only)
     -> tests -> G6 evaluator artifact.
   - Exit condition: all release/publish entrypoints are gated by G6 and fail
     closed on blocking findings.

4. Finish per-app migration verification matrix (5 apps):
   - Must verify one-shot import, then kernel-only reads/writes, no runtime
     legacy fallback branch execution.
   - Exit condition: targeted migration tests pass in each app repo.

## Green Criteria

Release is unblocked only when all four blocking items above are green.
