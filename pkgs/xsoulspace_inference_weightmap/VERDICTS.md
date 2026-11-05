# VERDICTS — weightmap ledger

Append-only. Every proposed direction, every run, every named failure gets a
row (the denominator lives here; selective reporting is structurally
impossible). Row format: date · arm · attempt-id · prediction · observation ·
verdict · receipt-digest.

| date | arm | attempt | prediction | observation | verdict | receipt |
|---|---|---|---|---|---|---|
| 2026-11-05 | program | setup | artifacts exist: HF edited checkpoint (Apache 2.0, 2-tensor SHA claim), lm_understand-logs exp1–exp8 + harness/ | verified live via HF/GitHub API | setup-ok | session receipt |
| 2026-11-05 | program | package | isolated package scaffolded; cast entry dispatched | — | in-flight | — |
| 2026-11-05 | setup | fetch | base Qwen/Qwen3.5-0.8B + RikiyaT edited fetched to hub cache (1.6G each) | FETCH-RECEIPT.sha256 written per repo | setup-ok | hub FETCH-RECEIPT ×2 |
| 2026-11-05 | cast | discovery | discovery generalized (org {mlx-community, Qwen}, family Qwen3.x); qwen3.5-0.8b discovered + resolves on switching surface (last_answer) | 6/6 discovery tests green; live hub probe ok | pass | mlx_native sampling test |
| 2026-11-05 | cast | load-gap | Qwen3.5-0.8B store is qwen3_5 hybrid arch + sharded safetensors; Rust engine load UNVERIFIED/expected-fail (named gap); generation blocked pending engine ADR or MLX conversion (uv venv route ready) | named non-claim | non-claim | cast agent report |
| 2026-11-05 | A1 | tooling | diff_safetensors.py + sha256_verify.py + fixtures implemented; 8/8 audit tests green (numpy and pure paths byte-identical receipts) | — | pass | audit_test |
| 2026-11-05 | contract | algebra | patch algebra (tolerance laws, conflicts), ledger chain, blinding gate, certification keys implemented; 58/58 tests green | — | pass | algebra tests |
| 2026-11-05 | evals | scorers | format-invariant + length-normalized scorers, IFEval subset, probe disjointness, capture/apply boundary scripts; 54/54 tests green | — | pass | scorer/probe/script tests |
| 2026-11-05 | program | integrate | whole-package analyze clean; 120/120 tests green; mlx_native discovery 6/6 green in integrated tree | — | pass | integrated run |
| 2026-11-05 | A1 | audit-run | claim: exactly 2 tensors differ (down_proj L15/L19), 131,072 elements; all others byte-identical | 2 tensors differ (model.language_model.layers.{15,19}.mlp.down_proj.weight, BF16 [1024,3584]); 130,188 elements differ (65,260 + 64,928); inventory match; all other tensors byte-identical | FAIL-count: ELEMENT_COUNT_BELOW_CLAIM (884 short of 131,072); shape criterion (2 tensors, rest byte-identical) met | receipts/A1-edit-audit.jsonl |
| 2026-11-05 | A1 | refinement | shortfall hypothesis: bf16 rounding absorption inside the claimed 64 target columns per layer | exactly 64 differing columns per tensor (non-contiguous), 0 diffs outside them; identical elements confined within target columns (276 + 608); L19 has one fully-identical row | observation: target set CONFIRMED at column granularity (64/64 columns, 2 layers); count shortfall is within-target, consistent with bf16 absorption — supported, NOT proven at rounding level (per-element direction unpublished) | session refinement script (pure-python, column mask) |

No verdicts yet. Phase A rows land with receipts.
