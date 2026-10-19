# xsoulspace_inference_openrouter

OpenRouter chat-completions transport for the provider-neutral inference
contracts. The current client supports text, structured output, and native
tool-call responses; the consumer executes tools.

An [optional decision provider plan](../xsoulspace_inference_core/docs/decision_provider_PLAN.md)
and separate [Jev pilot plan](docs/jev_pilot_PLAN.md) describe proposed work.
The decision adapter is not implemented and Jev is not a drop-in model setting
for the existing chat client. The proposed adapter remains disabled unless a
consumer explicitly constructs and registers it; it is not a harness feature
required for release.

The pilot separately evaluates target selection, evidence/hypothesis reasoning,
unseen semantic program composition, and mixed actors. Jev's API does not emit
source text; this does not rule out composing new behavior through successive
semantic choices materialized by a host. Such capability remains unmeasured.

From the workspace root, validate this package with
`just check xsoulspace_inference_openrouter`.

Explicit request `maxTokens` and `temperature` are forwarded as `max_tokens` and
`temperature`; consumers can therefore enforce a real output bound. Consumer
budgets and escalation remain host policy; provider usage is reported, not inferred.

Optional `diagnosticCapture` uses inference-core's generic context/cache events.
It captures the exact encoded request before HTTP only when
`includeEncodedBody` is explicitly enabled and the snapshot has complete
inspectable coverage; headers and arbitrary request metadata are excluded.
Default events contain hashes/lengths and reported numeric usage, not source.
The existing `onTransportDiagnostic` callback is unchanged and remains a
separate explicitly requested raw-body observer.

Explicit `context_cache_intent` metadata names encoded message/content-block
boundaries. Unknown support refuses with `cache_breakpoint_support_unknown`.
Only an explicitly selected `OpenRouterCacheBreakpointPolicy.anthropicEphemeral`
and an `anthropic/` model map the declared text block to
`cache_control: {type: ephemeral}` (at most four). No role or text is reordered,
and no default provider, routing, cache TTL, or policy is inferred. This narrow
mapping follows [OpenRouter's documented per-block dialect](https://openrouter.ai/docs/guides/best-practices/prompt-caching);
other provider/model routes remain unknown. Byte-prefix diagnostics are not
provider token counts, actual cache hits, plan consumption, or readiness proof.

The shared `context[0].content[0]` intent aliases the corresponding
`messages[0].content[0]` encoded position; existing message IDs remain valid and
diagnostics retain actual wire IDs. Codec ordering and roles stay unchanged.
Safe HTTP diagnostics include status, allowlisted code/type and an optional
parameter key/index path that exists in the encoded request, with presence flags
for omitted unknown values. No remote message, body, credential or header enters
the diagnostic event; authentication/rate-limit responses gain no new body
parsing. Existing result/error semantics and explicit legacy observers remain.

Generic HTTP diagnostics include the shared content-free rejection message hints
when code/param are null or absent. Fixed categories and parameter names can
identify an unsupported cache field without publishing the error message.

Optional generic events now include `transport`: normalized endpoint, redirect
policy, a process-local HTTP-client cohort, header-name inventory and SHA256
fingerprints of allowlisted cache/routing controls and response headers. No
authorization/cookie values or hashes, account identity, raw header values or
URL userinfo/query are retained. Unknown credential scope, connection reuse and
backend worker remain explicit. A response-header fingerprint is evidence of
equality, not worker identity or cache affinity. Request bytes/policy are unchanged.

`ContextCacheComparisonRequest` in `context_cache_comparison` metadata requests
provider-assisted comparison to a previous response. It is independent of cache
write intent. OpenAI maps it to `prompt_cache_options.comparison_response_id`;
unqualified OpenRouter routes fail before HTTP (`cache_comparison_unsupported`).
It is optional and never added to ordinary requests. Exact wire capture retains
the field; OpenAI declares that diagnostic-only path excluded from compatibility
configuration while mode/TTL changes remain visible. Actual route/model support
must be measured; public API documentation is not subscription qualification.

## Declarative session affinity

Attach the shared `InferenceSessionSpec` to an ordinary request. OpenRouter maps
its effective affinity key to body `session_id` and effective cache group to
`prompt_cache_key`. Body `session_id` takes routing precedence on OpenRouter;
cache grouping and actor identity remain separate in the caller. A turn change
leaves these stable keys unchanged. No OpenAI-specific headers or server tokens
are sent. Existing breakpoint dialect qualification remains independent.
Absent declarations preserve the existing wire shape. Provider stickiness is
best-effort, not a guaranteed model-worker pin or cache hit. Live OpenRouter
qualification is separate from deterministic request tests.
