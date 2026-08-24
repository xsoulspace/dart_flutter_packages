# A1 Fair Comparison — harness vs pi (same model via OpenRouter)

- Model: `nvidia/nemotron-3-nano-30b-a3b:free`
- Harness decision path: guided schema (`StructuredToolDecisionHandler`)
- pi decision path: native loop (`createAgentSession()`)
- Harness tokens: cumulative projection size per decision.
- pi tokens: real SDK usage (input+output+cache), asserted non-null by the driver.
- Retry parity: both columns get up to 2 checker-feedback rounds.

| task | harness pass | pi pass | harness cum tok | pi tok |
|---|---|---|---|---|
| bugfix_01_off_by_one | ❌ | ✅ | 1237 | 26891 |
| bugfix_02_null_crash | ❌ | ✅ | 1808 | 28444 |
| bugfix_03_write_failing_test_pass | ❌ | ✅ | 1469 | 26867 |
| chain_01_read_compute_write | ❌ | ✅ | 1035 | 21033 |
| chain_02_transform_pipeline | ❌ | ✅ | 1132 | 15685 |
| chain_03_multi_step_build | ❌ | ✅ | 1207 | 28921 |
| edit_01_rename_constant | ❌ | ✅ | 1126 | 22529 |
| edit_02_add_field | ❌ | ✅ | 1125 | 45585 |
| edit_03_fix_typo_string | ❌ | ✅ | 1314 | 29142 |
| edit_04_delete_function | ❌ | ✅ | 1092 | 33055 |
| edit_05_write_new_file | ❌ | ✅ | 1071 | 10724 |
| edit_06_json_config_update | ❌ | ✅ | 1051 | 149591 |
| refactor_01_extract_shared_function | ❌ | ✅ | 1960 | 102782 |
| refactor_02_rename_across_files | ❌ | ✅ | 1268 | 80849 |
| refactor_03_split_file | ❌ | ❌ | 1236 | 375787 |
| refactor_04_consistent_api | ❌ | ✅ | 1208 | 63395 |
| search_01_find_and_fix | ❌ | ✅ | 1156 | 22354 |
| search_02_which_file_uses_api | ❌ | ✅ | 1172 | 146615 |
| search_03_count_and_report | ❌ | ✅ | 1126 | 28142 |
| search_04_dead_code | ❌ | ✅ | 1133 | 34215 |

## Summary

| metric | harness+OR | pi+OR |
|---|---|---|
| pass rate | 0/20 (0%) | 19/20 (95%) |
| total tokens | 24926 | 1292606 |
| wall clock | 0:08:35.962000 | 0:15:29.921000 |

Failures remain data; failure modes live in the source JSONL.
