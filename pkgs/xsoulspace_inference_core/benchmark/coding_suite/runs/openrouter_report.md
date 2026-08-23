| task | category | pass | wall | tokens |
|---|---|---|---|---|
| bugfix_01_off_by_one | bug_fix_with_test | ❌ | 108607ms | 628 |
| bugfix_02_null_crash | bug_fix_with_test | ❌ | 123640ms | 581 |
| bugfix_03_write_failing_test_pass | bug_fix_with_test | ❌ | 243038ms | 581 |
| chain_01_read_compute_write | tool_chain | ❌ | 188203ms | 590 |
| chain_02_transform_pipeline | tool_chain | ✅ | 109807ms | 522 |
| chain_03_multi_step_build | tool_chain | ❌ | 180933ms | 485 |
| edit_01_rename_constant | file_edit | ❌ | 357773ms | 583 |
| edit_02_add_field | file_edit | ✅ | 66400ms | 647 |
| edit_03_fix_typo_string | file_edit | ✅ | 96313ms | 645 |
| edit_04_delete_function | file_edit | ❌ | 164700ms | 519 |
| edit_05_write_new_file | file_edit | ✅ | 74324ms | 523 |
| edit_06_json_config_update | file_edit | ❌ | 91516ms | 532 |
| refactor_01_extract_shared_function | multi_file_refactor | ❌ | 149636ms | 645 |
| refactor_02_rename_across_files | multi_file_refactor | ❌ | 52707ms | 806 |
| refactor_03_split_file | multi_file_refactor | ❌ | 124959ms | 793 |
| refactor_04_consistent_api | multi_file_refactor | ❌ | 73607ms | 725 |
| search_01_find_and_fix | search_then_edit | ❌ | 73844ms | 777 |
| search_02_which_file_uses_api | search_then_edit | ❌ | 190644ms | 793 |
| search_03_count_and_report | search_then_edit | ❌ | 63065ms | 716 |
| search_04_dead_code | search_then_edit | ❌ | 133128ms | 491 |

**harness**: 4/20 passed (20%), 12582 tokens total, 2666s wall clock.
