# ADR 0026 — The workspace is the domain: specs are data, the wire contract lives with the request

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `sub_star` — draws the ADR 0015 domain boundary at its
  TRUE seam: the map-graph/zoom/materializer machinery is domain-agnostic
  (workspace), only the per-language specs are domain content. Also amends
  where two misplaced pieces live (context-fragment protocol → core, wire
  codec → harness). This ADR does not change any semantics; it prevents the
  next duplication (md/json/text materializers forking a "dart"-owned
  registry, or every provider re-implementing wire rendering).
- Builds on: [0025](0025_host_layer_extraction_composable_embedding.md)
  (host layer, provider-thin), [0015](0015_domains_live_in_hosts_core_stays_generic.md)
  (domains in hosts), [0024](0024_filesystem_one_map_graph_typed_materializers.md)
  (materializer specs as data), [0018](0018_meaning_view_zoom_projection_context_ownership.md)

## Context

Post-0025 structural audit found the remaining misplacements:

1. **`xsoulspace_agentic_workspace` is misnamed by its own code.** Zero
   `package:analyzer` imports; `fs_etl.dart` explicitly indexes "EVERY file
   class, not just Dart"; `span_editor.dart` (1,737 loc, the largest file)
   is a generic span-splice engine. The Dart-ness is three files
   (`code_etl`, `test_etl`, `dart_materializer`). With the ADR 0024 §2
   md/yaml/json materializers landing for the pi dogfood, the registry,
   zoom and splice engine MUST NOT live in a package named "dart" — that is
   the meaning-tree-duplication seed.
2. **`ContextFragmentProtocol` lives in the harness but defines core's own
   request field** (`InferenceRequest.contextFragments`). A string protocol
   that core's public API depends on semantically belongs in core.
3. **`SituationMessagesCodec` (fragments → chat messages) lived in
   openrouter**, making a pure HTTP client import the engine. Wire
   rendering is a CONTRACT for core's fragment field; every future hosted
   provider would either import the engine or fork the codec.
4. **The in-process ACP duplex transport lives in last_answer** — every
   next embedder (or the pi SDK path) would copy it.
5. **Stress scenarios (harness `ScenarioRunner` cases) live in
   apple_foundation** — the last survivor of the 0025 disease.
6. Agents keep reintroducing raw coding (read/write loops, new bins in
   providers) — a procedural drift the structure alone does not stop.

## Decision

1. **`xsoulspace_agentic_workspace` is the domain host** (renamed from
   `xsoulspace_agentic_workspace`). It owns: the generic map-graph ETL
   (dir/file tier), zoom, the **materializer REGISTRY**, and the span-splice
   edit engine. Language support is a **spec family as data** under
   `dart/` semantics: `code_etl` + `test_etl` + `dart_materializer` stay,
   `md/`, `yaml/`, `json/`, `text/` families land beside them per ADR 0024.
   **Law: a new problem class lands as a materializer spec — never as a
   new loop, a new tool, or a raw read/write path.**

2. **`ContextFragmentProtocol` AND `SituationMessagesCodec` move to
   `xsoulspace_inference_core`.** The protocol defines core's own
   `contextFragments` field; the codec renders that field into the
   de-facto chat-completions `messages` shape — a wire CONTRACT, not
   engine policy. Providers opt in; openrouter is now the first truly
   pure hosted provider (`inference_core`-only). The harness re-exports
   both (no consumer breaks).

3. **The in-process ACP embed transport moves to `xsoulspace_agentic_host`**
   (`HarnessEmbed`): duplex channel + `AcpStdioServer` + `AcpClient` handshake
   + prompt/cancel/dispose. Consent policy (`PendingPermission` streams,
   UI routing) stays product-side in last_answer.

4. **Stress scenarios move to the harness** (`benchmark/stress/` +
   `bin/stress_cli.dart` with an injected router factory); apple_foundation
   keeps only provider smokes (`stream_smoke.dart`).

5. **Anti-drift law (pipeline_coding.md):** if you are adding a
   `read`/`write`/`grep`/`glob` tool, a driver `while(true)` oracle loop,
   or a `bin/` in a provider package, you are re-implementing
   ADR 0023/0024/0025 — stop and use the meaning profile, the budgeted
   gates, or a composition root. Enforced by the `pipeline.drift_check`
   steward action.

6. **Deferred (three-failures rule, recorded not speculative):**
   `ModelRouter` → `inference_core` (one host consumer today); pi extension
   package promotion (one driver today).

## Consequences

- md/json/text materializers land in `xsoulspace_agentic_workspace` beside
  the registry they extend — no second tree, no fork.
- openrouter (and every future hosted provider) depends only on core.
- last_answer's `harness_host.dart` shrinks to config + consent + doc
  binding; the transport is reusable as-is.
- The engine/domain/host/provider stack reads honestly:
  `inference_core` (contracts + protocol) → harness (engine + wire codec)
  → workspace (domain: specs) → host (transport/policy) → providers
  (transports) → products.
