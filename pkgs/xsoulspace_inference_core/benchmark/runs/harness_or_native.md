| task | category | pass | wall | tokens |
|---|---|---|---|---|
| bugfix_01_off_by_one | bug_fix_with_test | ✅ | 205498ms | 568 |
| bugfix_02_null_crash | bug_fix_with_test | ✅ | 93240ms | 286 |
| bugfix_03_write_failing_test_pass | bug_fix_with_test | ❌ | 26765ms | 286 |
| chain_01_read_compute_write | tool_chain | ❌ | 208599ms | 493 |
| chain_02_transform_pipeline | tool_chain | ✅ | 101554ms | 286 |
| chain_03_multi_step_build | tool_chain | ❌ | 281637ms | 481 |
| edit_01_rename_constant | file_edit | ❌ | 139672ms | 626 |
| edit_02_add_field | file_edit | ❌ | 280177ms | 551 |
| edit_03_fix_typo_string | file_edit | ❌ | 107156ms | 286 |
| edit_04_delete_function | file_edit | ✅ | 154368ms | 444 |
| edit_05_write_new_file | file_edit | ✅ | 11532ms | 286 |
| edit_06_json_config_update | file_edit | ✅ | 172831ms | 286 |
| refactor_01_extract_shared_function | multi_file_refactor | ❌ | 211433ms | 286 |
| refactor_02_rename_across_files | multi_file_refactor | ❌ | 279778ms | 425 |
| refactor_03_split_file | multi_file_refactor | ❌ | 119884ms | 286 |
| refactor_04_consistent_api | multi_file_refactor | ❌ | 181179ms | 286 |
| search_01_find_and_fix | search_then_edit | ❌ | 455908ms | 599 |
| search_02_which_file_uses_api | search_then_edit | ❌ | 63722ms | 286 |
| search_03_count_and_report | search_then_edit | ❌ | 226821ms | 422 |
| search_04_dead_code | search_then_edit | ❌ | 50738ms | 304 |

**harness**: 6/20 passed (30%), 7773 tokens total, 3372s wall clock.
