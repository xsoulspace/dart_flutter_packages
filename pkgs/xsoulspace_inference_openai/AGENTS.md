# Native OpenAI provider

DFP ADR 0067 owns the provider boundary. Read the workspace AGENTS.md.
Keep world context, actor scheduling, tool effects and acceptance in the caller.
Never read Codex credentials or add a CLI/agent loop to this provider.

Use the documented SIWC local/open-source flow. A fixture pass is not proof of
account eligibility, model access or release readiness. API-key fallback needs
an explicit separate user choice. Tokens never enter errors, logs or benchmarks.
Production endpoints are fixed; mock transports provide deterministic controls.
Credential stores must atomically replace records in protected storage. One
auth owner serves each store to serialize rotating refresh tokens.

From DFP root: `just check xsoulspace_inference_openai`. The lock-free Dart test
lane is `FLUTTER_ROOT=<sdk> dart test` from this package (not `dart test --no-pub`).
Native IO controls use local loopback only; no account credentials are required.
Update README/CHANGELOG for contracts and the parent delivery ledger for evidence.
