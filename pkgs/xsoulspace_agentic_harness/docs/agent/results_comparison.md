# A1 Fair Comparison — harness vs pi (same model via OpenRouter)

## Headline (final, published 2026-08 — A5 deliverable)

Same model (`poolside/laguna-xs-2.1:free`), same tasks, same retry parity:

| column       | backend | decision path | tokens source | tool surface | pass | tokens |
| ------------ | ------- | ------------- | ------------- | ------------ | ---- | ------ |
| harness+OR   | OpenRouter | native provider tool calling | cumulative projection size | 3 fs tools | 6/20 | 128k |
| pi+OR        | OpenRouter | pi SDK native loop | real SDK usage | pi built-ins | **19/20** | 1.29M |
| harness+OR (guided) | OpenRouter | guided schema `--decision guided` | cumulative projection size | 3 fs tools | 0/20 | — |

Read: guided schema is a bottleneck at tiny scale (C2). The remaining
harness-vs-pi gap is edit quality, not decision machinery — the lever A2
plan-frontier + decomposition attacks (scripted refactor tasks: −44…−72%
cumulative tokens at equal pass rate; see
[results_plan_falsification.md](results_plan_falsification.md)).
Full per-task table below; failure modes live in the source JSONL under
`benchmark/runs/`.

---

## Headline (final, published 2026-08 — A5 deliverable)

Same model (`poolside/laguna-xs-2.1:free`), same tasks, same retry parity:

| column       | backend | decision path | tokens source | tool surface | pass | tokens |
| ------------ | ------- | ------------- | ------------- | ------------ | ---- | ------ |
| harness+OR   | OpenRouter | native provider tool calling | cumulative projection size | 3 fs tools | 6/20 | 128k |
| pi+OR        | OpenRouter | pi SDK native loop | real SDK usage | pi built-ins | **19/20** | 1.29M |
| harness+OR (guided) | OpenRouter | guided schema `--decision guided` | cumulative projection size | 3 fs tools | 0/20 | — |

Read: guided schema is a bottleneck at tiny scale (C2). The remaining
harness-vs-pi gap is edit quality, not decision machinery — the lever A2
plan-frontier + decomposition attacks (scripted refactor tasks: −44…−72%
cumulative tokens at equal pass rate; see
[results_plan_falsification.md](results_plan_falsification.md)).
Full per-task table below; failure modes live in the source JSONL under
`benchmark/runs/`.

---

- Model: `poolside/laguna-xs-2.1:free`
- Harness decision path: native provider tool calling
  (`DefaultGenerationHandler`; guided-schema arm scored 0/20 — see below)
- pi decision path: native loop (`createAgentSession()`)
- Harness tokens: cumulative projection size per decision.
- pi tokens: real SDK usage (input+output+cache), asserted non-null by the driver.
- Retry parity: both columns get up to 2 checker-feedback rounds.

| task                                | harness pass | pi pass | harness cum tok | pi tok |
| ----------------------------------- | ------------ | ------- | --------------- | ------ |
| bugfix_01_off_by_one                | ✅           | ✅      | 8568            | 26891  |
| bugfix_02_null_crash                | ✅           | ✅      | 5564            | 28444  |
| bugfix_03_write_failing_test_pass   | ❌           | ✅      | 2521            | 26867  |
| chain_01_read_compute_write         | ❌           | ✅      | 5745            | 21033  |
| chain_02_transform_pipeline         | ✅           | ✅      | 3014            | 15685  |
| chain_03_multi_step_build           | ❌           | ✅      | 8578            | 28921  |
| edit_01_rename_constant             | ❌           | ✅      | 6112            | 22529  |
| edit_02_add_field                   | ❌           | ✅      | 10714           | 45585  |
| edit_03_fix_typo_string             | ❌           | ✅      | 3870            | 29142  |
| edit_04_delete_function             | ✅           | ✅      | 5948            | 33055  |
| edit_05_write_new_file              | ✅           | ✅      | 589             | 10724  |
| edit_06_json_config_update          | ✅           | ✅      | 7405            | 149591 |
| refactor_01_extract_shared_function | ❌           | ✅      | 9385            | 102782 |
| refactor_02_rename_across_files     | ❌           | ✅      | 11144           | 80849  |
| refactor_03_split_file              | ❌           | ❌      | 6497            | 375787 |
| refactor_04_consistent_api          | ❌           | ✅      | 6036            | 63395  |
| search_01_find_and_fix              | ❌           | ✅      | 16440           | 22354  |
| search_02_which_file_uses_api       | ❌           | ✅      | 3145            | 146615 |
| search_03_count_and_report          | ❌           | ✅      | 3630            | 28142  |
| search_04_dead_code                 | ❌           | ✅      | 3383            | 34215  |

## Summary

| metric       | harness+OR     | pi+OR          |
| ------------ | -------------- | -------------- |
| pass rate    | 6/20 (30%)     | 19/20 (95%)    |
| total tokens | 128288         | 1292606        |
| wall clock   | 0:56:12.492000 | 0:15:29.921000 |

### Guided-schema confound (C2 resolution)

The same model through the guided-schema path
(`StructuredToolDecisionHandler`) scored **0/20** with 2 total tool calls.
Switching to native provider tool calling restored 6/20 with 262 tool calls,
confirming C2: the guided-schema wrapper, not the model, was the bottleneck.

Remaining gap vs pi is edit quality (11 wrong-edit failures), not decision
machinery. The model can act; it writes incorrect content or targets the
wrong file. This is where A2 plan-frontier and decomposition mechanics should
close the remaining distance for tiny models.

Failures remain data; failure modes live in the source JSONL.
