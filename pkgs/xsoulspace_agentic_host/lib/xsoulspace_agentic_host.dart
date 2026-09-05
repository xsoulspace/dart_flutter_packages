library;

/// Host layer for the agentic harness (ADR 0025).
///
/// The host owns TRANSPORT + HOST POLICY and nothing else:
/// - `HarnessAcpBackend` — the `harnessd` ACP agent (world-per-workspace,
///   deny-by-default permissions, real cancellation, bounded escalation);
/// - `runHarnessdCli` — the daemon CLI (stdio + unix-socket transports,
///   single-instance lock, idle exit);
/// - `runCodingAgentOnce` / `taskFromSentence` — the coding runner core
///   (verifier inside the loop, pass@k protocol);
/// - `intent_closure_runner` — the on-device intent-closure driver.
///
/// Inference backends are INJECTED as `HarnessBackendBinding` entries by
/// the composition root (a thin bin in a provider package, an app, or a
/// test) — the host learns no provider.
export 'src/coding_agent_runner.dart';
export 'src/harness_acp_backend.dart';
export 'src/harness_embed.dart';
export 'src/harnessd_cli.dart';
export 'src/intent_closure_runner.dart';
