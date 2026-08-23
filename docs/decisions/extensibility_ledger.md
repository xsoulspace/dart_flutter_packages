# Extensibility Ledger

Per [ADR 0007 §4](0007_extensibility_seams_and_conformance.md): every occasion
the host needs a change to core gets an entry naming the pain, the seam
attempted, and the disposition. Three entries against the same seam trigger
the design conversation.

| Date | Pain / gap | Seam attempted | Disposition |
| --- | --- | --- | --- |
| 2026-08-25 | Phase 4 hosted comparison requires pi driving the harness via ACP/MCP; no server implementation of the harness as an ACP/MCP server exists (verified: nothing under `pkgs/xsoulspace_inference_apple_foundation/bin/`). The pi-vs-harness column cannot be produced inside Phase 4. | Seam 2 (hosting/`GenerationHandler` adapters) and MCP interop surface (ADR 0007 §3) | **Gap recorded, not built inside Phase 4.** Interim comparison uses harness + OpenRouter-hosted model (`bin/coding_suite_openrouter.dart`), labeled explicitly as *harness+hosted*, NOT pi-vs-harness. Building the ACP/MCP server remains future work before the headline claim is testable. **Update:** resolved differently — pi's SDK (`createAgentSession`) + its native OpenRouter support make a server unnecessary for the comparison; see `pkgs/xsoulspace_inference_core/docs/agent/plan_fair_pi_comparison.md`. |
| 2026-08-25 | Hosted-model columns underperform partly due to input shape: `OpenRouterInferenceClient` flattens projected context into a single user message ("CONTEXT:" text block) instead of a multi-turn chat-completions `messages` array — no assistant/tool roles, so hosted models get off-distribution input. Code carries `TODO(arenukvern): this is wrong - should be rewritten to messages (completion api)`. | Seam 2 (`InferenceClient` adapter, provider package only) | **To fix inside the provider package** (`openrouter_inference_client.dart`) — proper `messages` mapping + real usage reporting from `decoded['usage']`, keeping the current path behind a flag for an A/B cost measurement. No core change required. |
