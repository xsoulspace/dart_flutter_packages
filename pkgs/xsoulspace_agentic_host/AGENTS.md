# pkgs/xsoulspace_agentic_host: Agent Working Agreement

The HOST layer (ADR 0025): transport + host policy for the agentic
harness — nothing else. Engine work → `xsoulspace_agentic_harness`; Dart
domain work → `xsoulspace_agentic_workspace`; provider/FFI work →
`xsoulspace_inference_apple_foundation` / `xsoulspace_inference_openrouter`;
product work → `last_answer`. This package must stay learnable in one
sitting: 4 lib files, no providers, no app code.

## Layout

| Path | Role |
| --- | --- |
| `lib/src/harness_acp_backend.dart` | `HarnessAcpBackend` — the `harnessd` ACP agent: world-per-workspace, snapshot restore, deny-by-default permissions, real cancellation, bounded monotonic escalation. Backends injected as `HarnessBackendBinding`. |
| `lib/src/harnessd_cli.dart` | `runHarnessdCli` — the ONE canonical daemon CLI (stdio + unix socket, single-instance lock, idle exit). |
| `lib/src/harness_embed.dart` | `HarnessEmbed` — in-process ACP transport (ADR 0026 §3): duplex channel + `AcpStdioServer` + `AcpClient`; apps embed without subprocesses. |
| `lib/src/coding_agent_runner.dart` | Coding runner core: `runCodingAgentOnce`, `taskFromSentence`, task specs as data, verifier inside the loop, pass@k protocol. |
| `lib/src/intent_closure_runner.dart` | On-device intent-closure driver (J1.4). |
| `bin/harnessd.dart` | Provider-less daemon entrypoint — `--scripted` / `--remote-mover` out of the box, no mover model. |

## Embedding (ADR 0025)

- **SDK:** `HarnessEmbed.start(backend: HarnessAcpBackend(bindings: {…}))`
  → in-process daemon over a duplex channel; `delegateTask`/`cancel`/`stop`.
  Consent policy stays product-side (`AcpPermissionDelegate`).
- **ACP:** run `runHarnessdCli` (or a composition root's bin) and attach
  over stdio or the unix socket (`<ws>/.dart_tool/harnessd/harnessd.sock`).
- Provider composition root example:
  `xsoulspace_inference_apple_foundation/bin/harnessd.dart`.

## Invariants

- No provider imports (no `inference_openrouter`, no AFM native bridge).
- No ACP vocabulary in the harness engine (D5); no second protocol, ever.
- Deny-by-default permissions; `maxGoalAttempts` hard-capped at 9, never reset.
- Single-instance per workspace is MANDATORY.

## Validation

```bash
cd pkgs/xsoulspace_agentic_host
flutter pub get && dart analyze && flutter test
```
