| task | category | pass | wall | tokens |
|---|---|---|---|---|
| bugfix_01_off_by_one | bug_fix_with_test | ❌ | 119401ms | 603 |
| bugfix_02_null_crash | bug_fix_with_test | ❌ | 184876ms | 530 |
| bugfix_03_write_failing_test_pass | bug_fix_with_test | ❌ | 89436ms | 629 |
| chain_01_read_compute_write | tool_chain | ❌ | 215728ms | 484 |
| chain_02_transform_pipeline | tool_chain | ❌ | 49054ms | 603 |
| chain_03_multi_step_build | tool_chain | ❌ | 78837ms | 744 |
| edit_01_rename_constant | file_edit | ✅ | 126632ms | 547 |
| edit_02_add_field | file_edit | ✅ | 274531ms | 725 |
| edit_03_fix_typo_string | file_edit | ❌ | 50964ms | 547 |
| edit_04_delete_function | file_edit | ❌ | 41236ms | 719 |
| edit_05_write_new_file | file_edit | ✅ | 34189ms | 662 |
| edit_06_json_config_update | file_edit | ✅ | 25827ms | 558 |
| refactor_01_extract_shared_function | multi_file_refactor | ❌ | 74955ms | 938 |
| refactor_02_rename_across_files | multi_file_refactor | ❌ | 73700ms | 794 |
| refactor_03_split_file | multi_file_refactor | ❌ | 241962ms | 839 |
| refactor_04_consistent_api | multi_file_refactor | ❌ | 170882ms | 672 |
| search_01_find_and_fix | search_then_edit | ✅ | 147711ms | 824 |
| search_02_which_file_uses_api | search_then_edit | ❌ | 245961ms | 773 |
| search_03_count_and_report | search_then_edit | ❌ | 78862ms | 542 |
| search_04_dead_code | search_then_edit | ❌ | 91622ms | 659 |

**harness**: 5/20 passed (25%), 13392 tokens total, 2416s wall clock.
