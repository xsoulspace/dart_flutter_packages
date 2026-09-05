# ADR 0027 seam speed — measured (AFM backend, real device)

Backend: `apple_foundation_afm` (AppleFoundationNativeClient), meaning
profile, workspace = bare-file fixture. Published pre-0027 reference: a
read decision cost ~68,775 ms (the `dart test` cold compile in the final
gate — results_r7.md).

| prompt class | wall | gate | surface |
| --- | --- | --- | --- |
| `directive read [scan][zoom]` | 51 ms | no-task (mechanical) | cuts streamed |
| `[read-only] free-form` | 44099 ms | no-grade (declared read) | cuts streamed |
| `mutation task (baseline)` | 63682 ms | full oracle | cuts streamed |

## Reading

- The directive read is MECHANICAL: zero model, zero grade — its wall is
  ETL + zoom only (two orders below the 68s row).
- The `[read-only]` delegation pays AFM latency only; the gate is stamped
  `read_only_not_applicable` (excluded from pass-rate columns).
- The mutation baseline keeps the FULL oracle (verifier inside the loop +
  final gate) — the honest-oracle law is untouched.

Rows are published even on FAIL, with backend + tokens source (AFM
on-device, no token billing) per the standing rules.
