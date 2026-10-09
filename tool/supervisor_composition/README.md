# supervisor_composition

Observe-only supervisor composition declaring this repo's local model
serving on the shipped oka substrate — the oka supervisor guide roadmap
step "dfp model composition on the shipped substrate"
([oka ADR-0040](https://github.com/Arenukvern/oka/blob/main/docs/decisions/0040-declarative-supervisor.mdx)
R1, [ADR-0041](https://github.com/Arenukvern/oka/blob/main/docs/decisions/0041-supervisor-adoption-ladder.mdx)
L0).

Why: on 2026-10-08 a consult failed because nothing was serving and the
wire model id had drifted from the served checkpoint (oka ADR-0039
context). The endpoint facts existed only in code and README conventions.
This package declares those facts as supervisor components, so a plain
`converge(apply: false)` turns "the laya endpoint is down" or "the model
id drifted" into a supervisor **finding** before anyone consults the
model — instead of a surprise at consult time.

## The never-spawn law

This composition never starts, stops, or signals anything:

- every spec names the `observe-only` provider
  (`lib/desired.dart`, `ObserveOnlyProvider`), whose `start` throws
  `StateError('observe-only composition never starts processes')`,
  whose `stop` refuses, and whose `inspect`/`reconcile` report
  `unknown` (report-never-guess);
- the only supported mode is `Supervisor.converge(apply: false)` —
  read-only observation, plan + findings, nothing mutated (oka ADR-0040
  decision 5: foreign and hand-started processes produce findings, never
  signals);
- both specs declare `maxRestarts: 0`: the posture is policy, not
  convention.

When the ADR-0039 serve-core provider lane lands, its provider name
replaces `observe-only` here and nothing else in the declaration moves.

## Declared components

| id | shape | readiness | trigger | meaning |
|---|---|---|---|---|
| `model-serve` | service | `TcpConnect(127.0.0.1, 8765)` | none | the local model server; a connected socket means ready to generate (the entrypoints load the weights before binding) |
| `nightly-model-audit` | job | — | `IntervalTrigger(24h)`, record-only | the nightly audit cadence as a schedule declaration; nothing here runs it |

`model-serve`'s env declares the expected wire model ids
(`MODEL_ID_EXPECTED: qwen3-0.6b-4bit`, `MODEL_ID_FALLBACK:
lfm2.5-1.2b-instruct-mlx-4bit`) for visibility and revision hashing (the
spec env law, oka ADR-0040 decision 8). A `/health` payload that stops
announcing the expected id is the drift class the 2026-10-08 incident
made visible.

## Discovered endpoint facts (read-only recon, file:line)

Paths relative to this repo root:

- **Host: loopback only.** `HttpServer.bind(address ??
  InternetAddress.loopbackIPv4, port)` —
  `pkgs/xsoulspace_inference_local_serve/lib/src/loopback_json_server.dart:108`
  (field doc "Defaults to the loopback interface", line 70).
- **Port: 8765, pinned by the serve entrypoints.**
  `pkgs/xsoulspace_inference_mlx_native/tool/serve_text.dart:21`
  (`var port = 8765`, flag `--port`) and
  `pkgs/xsoulspace_inference_mlx/bin/mlx_serve_native.dart:28`.
  Client-side discovery mirrors it:
  `pkgs/xsoulspace_inference_mlx/lib/src/mlx_serve_runtime.dart:39`
  (`static const int defaultPort = 8765`; `defaultEndpoint()` line 41).
  Caveat: the in-process server classes default to an ephemeral port
  (`final int port = 0` — `LayaLfm2ChatServer`,
  `laya_native_lfm2_client.dart:295`; `LayaQwenChatServer`,
  `laya_native_qwen_client.dart:203`); a stable address exists only
  through the entrypoints above.
- **Health: `GET /health`, always open.**
  `loopback_json_server.dart:56` (`this.healthPath = '/health'`) and
  lines 172–175 (the health route answers JSON without auth);
  `serve_text.dart:75` prints the same contract
  (`health: $url/health`).
- **Model id rides the health payload.** `healthPayload` returns
  `{'status': 'ok', 'model': model, 'engine': ...}` —
  `laya_native_lfm2_client.dart:303-307` (`engine: 'laya-native-lfm2'`)
  and `laya_native_qwen_client.dart:211-215`
  (`engine: 'laya-native-qwen'`). Wire model id defaults:
  `'lfm2.5-1.2b-instruct-mlx-4bit'`
  (`laya_native_lfm2_client.dart:292`), `'qwen3-0.6b-4bit'`
  (`laya_native_qwen_client.dart:200`); the `mlx_serve_native.dart`
  entrypoint announces `'mlx_text_native'` (line 92).
- **Chat wire:** `POST /v1/chat/completions`
  (`laya_native_lfm2_client.dart:346`).
- **Socket up = ready.** The entrypoints load the checkpoint before
  binding (`serve_text.dart:43-47`: `await NativeLfm2TextEngine.load()`
  before `server.start()`); `mlx_serve_runtime.dart:30-32` records the
  same contract for the Python server ("the server binds only after the
  model has loaded, so 'answering' means 'ready to generate'"). That is
  why the readiness dialect is a plain `TcpConnect`, not a handshake.
- **One-shot liveness probe precedent:**
  `pkgs/xsoulspace_inference_local_serve/lib/src/local_health_probe.dart:24-35`
  — any answering status below 500 counts as alive; this composition
  deliberately does less (no probe at all).

## Nightly carrier findings (recon, nothing modified)

- No schedule carrier exists in this repo: `tool/universal_storage_*
  audit*.{sh,py}` are one-shot scripts with no schedule declarations;
  no launchd plist, cron file, or watcher spec references them or the
  model lane.
- The nightly cadence is a machine-level cron outside both repos
  (03:00 text-model lane — switched to the Qwen3 cast on the
  2026-10-08 napbench verdict; 04:00 nap lane). Because that schedule
  is declared nowhere in-repo, a silently dead nightly is invisible —
  which is exactly what the record-only `nightly-model-audit` job
  exists to surface.

## Run it

```bash
cd tool/supervisor_composition
dart pub get
dart run bin/observe.dart                 # human-readable plan + findings
dart run bin/observe.dart --json          # + statusJson/findings document
dart run bin/observe.dart --facts facts.jsonl   # + append JSONL events
dart run bin/observe.dart --port 9999     # declare/observe another port
dart test
```

`--project` defaults to the repo root containing this package; `--port`
overrides the declared (and re-hashed) readiness port. Exit code 2 means
the declaration itself failed validation. The converge is read-only: no
process is spawned, no signal is sent, and no registry record is written.

First real run (2026-10-10): nothing was listening on 127.0.0.1:8765, so
the plan reported `start model-serve (declared service with no record)`
and `start nightly-model-audit` — the 2026-10-08 incident class, now a
finding. Evidence:
`docs/evidence/supervisor-composition-observe-2026-10-10.log`.

## Constraints honored

- `oka` is read-only here; the path dependencies root at the local oka
  checkout (`dependency_overrides` forces the path source of
  `resource_composition` over the hosted constraint its oka consumers
  declare).
- No file outside `tool/supervisor_composition/` and the one evidence
  log is touched by this package.
