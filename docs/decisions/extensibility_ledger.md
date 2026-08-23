# Extensibility Ledger

Per [ADR 0007 §4](0007_extensibility_seams_and_conformance.md): every occasion
the host needs a change to core gets an entry naming the pain, the seam
attempted, and the disposition. Three entries against the same seam trigger
the design conversation.

| Date | Pain / gap | Seam attempted | Disposition |
| --- | --- | --- | --- |
| 2026-08-25 | Phase 4 hosted comparison requires pi driving the harness via ACP/MCP; no server implementation of the harness as an ACP/MCP server exists (verified: nothing under `pkgs/xsoulspace_inference_apple_foundation/bin/`). The pi-vs-harness column cannot be produced inside Phase 4. | Seam 2 (hosting/`GenerationHandler` adapters) and MCP interop surface (ADR 0007 §3) | **Gap recorded, not built inside Phase 4.** Interim comparison uses harness + OpenRouter-hosted model (`bin/coding_suite_openrouter.dart`), labeled explicitly as *harness+hosted*, NOT pi-vs-harness. Building the ACP/MCP server remains future work before the headline claim is testable. |
