/// Desired state for dart_flutter_packages' local model serving, declared
/// on the shipped supervisor substrate (oka ADR-0040 R1, ADR-0041 L0; the
/// oka supervisor guide roadmap step "dfp model composition on the
/// shipped substrate").
///
/// Observe-only by construction: every spec names
/// [ObserveOnlyProvider.name] and the composition root binds
/// [ObserveOnlyProvider], whose `start` throws. Converge runs with
/// `apply: false`, so this composition can never spawn a process and
/// never signal one — "the laya endpoint is down / the model id drifted"
/// becomes a supervisor finding at converge time instead of a surprise at
/// consult time (the 2026-10-08 incident class, oka ADR-0039 context).
///
/// ADR-0039 alignment (terminology only; that ADR's provider is NOT
/// implemented here): one component per served cast, consumers bind
/// outputs — never endpoints; spawn/probe/stop mechanics belong to a
/// serve provider. When the ADR-0039 serve-core provider lane lands, its
/// provider name replaces [ObserveOnlyProvider.name] and nothing else in
/// this declaration moves.
library;

import 'package:oka_supervisor/oka_supervisor.dart';
import 'package:resource_composition/resource_composition.dart';

/// Endpoint facts of the local model serve lane, discovered by read-only
/// recon of the serving packages (file:line citations in README.md). The
/// declared readiness dialect matches this reality.
///
/// The serve entrypoints pin a fixed loopback endpoint; the in-process
/// server classes themselves default to an ephemeral port and are
/// reachable at a stable address only through those entrypoints.
abstract final class ModelServeFacts {
  /// Loopback-only bind: `HttpServer.bind(address ??
  /// InternetAddress.loopbackIPv4, port)` —
  /// pkgs/xsoulspace_inference_local_serve/lib/src/loopback_json_server.dart:108
  /// (field doc "Defaults to the loopback interface", line 70).
  static const String host = '127.0.0.1';

  /// Both serve entrypoints default to 8765:
  /// pkgs/xsoulspace_inference_mlx_native/tool/serve_text.dart:21 and
  /// pkgs/xsoulspace_inference_mlx/bin/mlx_serve_native.dart:28; client
  /// discovery mirrors it (`MlxServeRuntime.defaultPort`,
  /// pkgs/xsoulspace_inference_mlx/lib/src/mlx_serve_runtime.dart:39,
  /// `defaultEndpoint()` line 41).
  static const int port = 8765;

  /// The open health route (`LoopbackJsonServer.healthPath` default,
  /// loopback_json_server.dart:56); its JSON payload names the served
  /// model id (`healthPayload` closures,
  /// pkgs/xsoulspace_inference_mlx_native/lib/src/laya_native_lfm2_client.dart:303-307
  /// and pkgs/xsoulspace_inference_mlx_native/lib/src/laya_native_qwen_client.dart:211-215).
  static const String healthPath = '/health';

  /// The OpenAI-compatible chat route
  /// (laya_native_lfm2_client.dart:346).
  static const String chatPath = '/v1/chat/completions';

  /// Wire model id the qwen cast announces (`LayaQwenChatServer.model`
  /// default, laya_native_qwen_client.dart:200) — the nightly's primary
  /// cast since the 2026-10-08 napbench verdict.
  static const String qwenModelId = 'qwen3-0.6b-4bit';

  /// Wire model id the lfm2 cast announces (`LayaLfm2ChatServer.model`
  /// default, laya_native_lfm2_client.dart:292).
  static const String lfm2ModelId = 'lfm2.5-1.2b-instruct-mlx-4bit';
}

/// The provider every spec in this composition binds.
///
/// Laws (oka ADR-0040 decision 5): foreign and hand-started processes
/// produce findings, never signals. `start` throws (this composition
/// never spawns); `stop` refuses (never signals); `inspect`/`reconcile`
/// report `unknown` — report-never-guess, no probe is authorized here.
final class ObserveOnlyProvider implements ResourceProvider {
  /// Creates the provider; pure at composition time — nothing contacted.
  const ObserveOnlyProvider();

  /// The provider name every spec in this composition declares.
  static const String name = 'observe-only';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  Future<StartReport> start(final StartRequest request) => Future.error(
    StateError('observe-only composition never starts processes'),
  );

  @override
  Future<Observation> inspect(final ResourceRef ref) => Future.value(
    const Observation(
      state: ResourceState.unknown,
      cause: TerminalCause.unknown,
      message: 'observe-only: liveness unprovable without a record from '
          'a start; report-never-guess',
    ),
  );

  @override
  Future<StopReport> stop(
    final ResourceRef ref, {
    required final Duration grace,
  }) => Future.value(
    const StopReport(
      disposition: StopDisposition.refused,
      message: 'observe-only composition never signals a process',
    ),
  );

  @override
  Future<Observation> reconcile(final ResourceRef ref) => inspect(ref);
}

/// The local model server as a service component: desired running, with
/// the discovered readiness dialect. A connected socket means ready to
/// generate: the entrypoints load the weights before binding
/// (serve_text.dart:43-47 constructs the engine with `await ...load()`
/// before `server.start()`; mlx_serve_runtime.dart:30-32 records the same
/// contract for the Python server).
///
/// The spec's env declares the expected wire model ids for visibility and
/// revision hashing (the spec env law, oka ADR-0040 decision 8) — a
/// server whose `/health` payload stops announcing
/// [ModelServeFacts.qwenModelId] is exactly the drift the 2026-10-08
/// incident made visible (wire model id resolved as a Hugging Face repo
/// at request time, a 404 at consult time).
///
/// `maxRestarts: 0` encodes the observe-only posture as policy: even a
/// hypothetical apply pass never restarts anything.
ComponentSpec modelServeSpec({final int port = ModelServeFacts.port}) =>
    ComponentSpec(
      id: 'model-serve',
      providerName: ObserveOnlyProvider.name,
      readiness: TcpConnect(ModelServeFacts.host, port),
      policy: const SupervisionPolicy(maxRestarts: 0),
      env: <String, String>{
        'SERVE_HOST': ModelServeFacts.host,
        'SERVE_PORT': '$port',
        'SERVE_HEALTH_PATH': ModelServeFacts.healthPath,
        'SERVE_CHAT_PATH': ModelServeFacts.chatPath,
        'MODEL_ID_EXPECTED': ModelServeFacts.qwenModelId,
        'MODEL_ID_FALLBACK': ModelServeFacts.lfm2ModelId,
      },
    );

/// The nightly model audit as a job component: a schedule declaration
/// only. The nightly cadence runs from a machine-level cron (03:00
/// text-model lane, switched to the Qwen3 cast on the 2026-10-08
/// napbench verdict; 04:00 nap lane) that is declared nowhere in this
/// repo — recording it on the substrate makes a silently dead schedule a
/// diffable desired-vs-actual finding instead of an absence nobody owns
/// (oka ADR-0040 context). Nothing here runs it:
/// [ObserveOnlyProvider] never spawns, `maxRestarts: 0`, and the only
/// supported converge is `apply: false`.
const ComponentSpec nightlyModelAuditSpec = ComponentSpec(
  id: 'nightly-model-audit',
  providerName: ObserveOnlyProvider.name,
  policy: SupervisionPolicy(
    shape: SupervisionShape.job,
    maxRestarts: 0,
  ),
  trigger: IntervalTrigger(period: Duration(hours: 24)),
  env: <String, String>{
    'AUDIT_CARRIER': 'host cron 03:00 nightly (machine-level; not '
        'declared in this repo)',
    'AUDIT_PRIMARY_MODEL': ModelServeFacts.qwenModelId,
  },
);

/// The whole desired state: the model-serve service plus the record-only
/// nightly audit job. Validate-before-side-effects applies unchanged —
/// `DesiredState.validate` contacts no provider.
DesiredState desiredComposition({final int? port}) => DesiredState(
  specs: [
    modelServeSpec(port: port ?? ModelServeFacts.port),
    nightlyModelAuditSpec,
  ],
);
