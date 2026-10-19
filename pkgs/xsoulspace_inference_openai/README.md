# xsoulspace_inference_openai

Native ChatGPT-plan authorization and Responses inference for eligible locally
hosted/open-source applications. Under development; no live account or product
adoption has been qualified. See [ADR 0067](../../docs/decisions/0067_native_chatgpt_plan_inference.md).

Applications supply a `ChatGptCredentialStore` backed by protected local storage
and a system-browser launcher. Persist `ChatGptAuth.createHostId()` once per
installation. Keep issued client/account records separate and never log their
storage serialization or authorization URLs. A browser identity-only grant is
retained with `planEnabled == false` and cannot perform inference.

```dart
final auth = ChatGptAuth(store: protectedStore);
final callback = await ChatGptLoopback.bind();
final account = await callback.authorize(
  auth: auth,
  hostId: persistedHostId,
  appName: 'Last Answer',
  openBrowser: launchSystemBrowser,
);
final client = OpenAiResponsesClient(
  auth: auth,
  clientId: account.clientId,
  model: selectedAccountModelSlug,
);
final result = await client.infer(InferenceRequest(prompt: 'Current decision'));
```

List models with `client.listModels()`; it uses the selected account's token and
preserves server order. Catalog presence is not entitlement proof. A successful
terminal inference response is the request's access evidence.

`infer` returns proposed `toolCalls` and original items in
`data.meta['responses_output']`; it never executes the `ToolRegistry` callbacks.
Use `ResponsesInput` to render currently authorized continuation items and
`ResponsesInput.toolOutput(callId, output)` for correlated results. The calling
host owns durable evidence, context selection, execution and acceptance. Native
tool IDs are required: text-only `ChatMessage.tool` refuses. Legacy context tool
fragments render as observed notes, not invented function call outputs.

The subscription preview requires explicit context, `store:false`, `stream:true`
and supported local namespaced tools. Unsupported generation knobs refuse before
transport. Cancellation aborts native HTTP; disposing a session waits for the
provider operation to settle. Input/token budgets remain a host concern; the
provider enforces a deadline and bounded response bytes. SSE text is provisional
until `response.completed`. Late subscription failure, incomplete responses,
EOF and cancellation are separate failures. No automatic request/tool replay.

Token refresh coalesces per registration inside one auth owner. Do not instantiate
independent auth owners over one rotating-token store in different processes.
`signOut` clears local tokens and returns whether remote revocation was confirmed.
Account/host mapping belongs to the store and survives token removal.

Authorization, refresh and sign-out share one registration mutation lane.
Cancellation waits for authorization/storage settlement, restores an interrupted
publication, and attempts revocation of any acquired token set. Failed rollback
fences that registration from inference in the current auth owner. Unconfirmed
remote cleanup is exposed through `hasUnconfirmedAuthorizationCleanup` and
sign-out's result. Stores implementing `RecoverableChatGptCredentialStore` persist a mutation fence
before remote token mutation. Interrupted/failed publication refuses ordinary reads
across auth-owner restart until explicit reauthorization or signout. Last Answer
implements this in its protected bundle. Stores implementing only the base interface
retain process-local controls. Real platform crash/keychain fault injection still
needs qualification; reconstructed in-memory storage is not that proof. Closing a browser listener waits for this cleanup,
which can take several bounded auth requests; it is not immediate network abort.

Native `streamResponses(request, toolRegistry: registry)` advertises host-supplied
tools. The legacy core structured stream has no registry parameter and advertises
none. All returned function calls must belong to the supplied registry. Continuation
items add to the current context cut; they cannot replace its mandatory facts.

Native contract gate: `just check xsoulspace_inference_openai` from DFP root.

Core kind-tagged schema bundles are converted with the shared JSON-Schema
converter before transport. Function and text-format schemas explicitly use
`strict:false` to retain optional fields; completed structured text is validated
locally. This qualifies inline types, enum, required keys, nullable alternatives,
closed properties and array bounds, not all core guides or JSON-Schema drafts.
Unresolved references refuse as `schema_unsupported` before dispatch. HTTP
refusals retain numeric status and only fixed diagnostic categories/families from
a bounded 16 KiB body; remote messages and parameter contents are never emitted.
Tests use signed synthetic identities, HTTP mocks and actual local IO cancellation;
they never call OpenAI or require secrets. Live registration, eligibility,
renewal/revocation and end-to-end harness behavior remain delivery gates.

`CancellableInferenceClient` is an optional core lifetime. Create separate provider
instances for independently cancellable actor/session requests while sharing one
auth owner. `cancelActive()` cancels this instance's catalog and inference work;
`settleActive()` waits for physical settlement. A signed-out returning account
may use `ChatGptRegistration` without access/refresh tokens or an ID-token hint.

`cancelAuthorization(attempt)` returns an acknowledgment: recoverable stores
persist cancellation intent before it completes. Await it and then
`settleAuthorization` before releasing the caller's ownership. Ordinary durable
commit refuses that intent; explicit rollback restores healthy prior credentials
and settles acquired-token cleanup. Failed recovery leaves an abandoned fence
intact. Cancellation requested before acknowledgment and arbitrary OS storage
failure remain distinct from a durable acknowledged cancellation.

`finishMutation` records unconfirmed remote cleanup independently from local
token removal. Reauthorization or a later successful revocation cannot erase an
older unknown remote outcome. The auth object's cleanup getter reports its
observations; applications also load their store's durable uncertainty projection.

`observeDecision` optionally receives a settled `ResponsesDecisionReceipt` with
advertised-tool/schema flags, observed HTTP status, elapsed time, fixed terminal
output-kind counts, streamed/wire/parsed text lengths, parsed call/key counts and
allowlisted nonnegative numeric usage (including reported cache-write tokens).
Receipts also expose sorted advertised tool names and SHA-256/UTF-8 byte counts
for encoded request instructions, tools, input, reasoning options and output
format. Per-input segment fingerprints are capped at 64 with an omitted count;
encrypted continuation fields are excluded from fingerprints. Hashes reveal
request equality, so keep receipts within the authorized diagnostic boundary.
They carry no text, arguments, IDs or credentials. Observer exceptions cannot alter inference; keep this synchronous
callback quick because physical settlement waits for it. These diagnostics do not
grant authority or prove tool execution, acceptance, or shared-auth settlement.

Final `response.output_item.done` items are retained by index. A valid completed
terminal admits them when its output array is empty; otherwise terminal and
streamed items must agree after canonical key ordering. Index gaps, conflicting
items and explicit noncompleted item status refuse. Item-done/argument deltas alone
never establish inference success. The real SIWC path emitted a final function
item with an empty terminal array; dropping that item had produced empty decisions.

Package controls use one test lane so CPU-intensive identity fixtures do not
starve bounded native IO controls. Physical deadlines remain unchanged. Test
servers explicitly flush streaming output; a server flush does not prove that
client headers were observed before interruption.

Explicit `InferenceRequest(reasoningEffort: 'low', ...)` emits
`reasoning: {effort: low}`. Null retains the endpoint default; `thinking` is not
translated into effort. Supported wire values are advertised through the optional
core capability; model eligibility remains a server decision. Unknown values
refuse before dispatch. Safe decision receipts include only recognized effort.
The shared `streamWithTools` capability forwards the existing SSE path and keeps
completed typed calls/results intact; it never executes them.

Optional `diagnosticCapture: ContextTransportDiagnosticCapture(...)` observes
the exact encoded request before HTTP and its settled numeric usage. Default
events contain only digests, lengths and safe structural metadata. Exact source
body export requires `includeEncodedBody: true` and complete inspectable
coverage; encrypted/opaque continuation content is never exported. Observer
exceptions cannot affect results or physical settlement. Optional decision
receipts reuse the same `contextDiagnostic` snapshot and retain usage-field
presence, so missing cache counts stay distinct from reported zero. Actual
response ID/model/service tier and allowlisted cache diagnostic enums/counts
appear only with generic diagnostics enabled; no headers or arbitrary remote
diagnostic text is captured.

Explicit `context_cache_intent` metadata uses core `ContextCacheIntent` and
encoded paths such as `input[0].content[0]`. For documented GPT-5.6+ model names,
declared text blocks receive `prompt_cache_breakpoint: {mode: explicit}`.
Message-end intent can wrap the same string in a single `input_text` block;
roles/text/order remain unchanged. Request-wide implicit policy is preserved,
so this profile permits at most three explicit writes. Unknown models or
unsupported boundaries refuse before dispatch; no cache key, TTL or output
bound is invented.

The [OpenAI cache guide](https://developers.openai.com/api/docs/guides/prompt-caching)
documents the modern API policy, and the
[cache diagnostics guide](https://developers.openai.com/api/docs/guides/prompt-caching/diagnostics)
documents optional response comparison results. The current
[SIWC inference guide](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
does not separately qualify these cache options for the subscription route.
Endpoint support therefore stays explicitly unknown until that exact route is
measured. UTF-8 JSON prefix evidence is not hidden provider tokens, a cache hit,
subscription consumption, or product acceptance. No live request is required
for deterministic package controls.

Provider-neutral `context[0].content[0]` intent aliases the corresponding
`input[0].content[0]` wire position; existing input IDs remain valid. Diagnostics
retain actual encoded IDs. This does not reorder provider codecs or equate JSON
key order (including `instructions`) with the model's rendered prompt order.
Implicit endpoint candidates exclude assistant endings, include user endings
and only the final output in a consecutive tool-output group, and retain the
initial instruction analogue as unqualified evidence.

HTTP failure diagnostics add status and optional allowlisted code/type plus a
parameter path only when its keys/indices exist in the encoded request. Unknown
values stay null with explicit presence flags. Error messages, bodies, headers
and credentials never enter these fields. Existing error categories and the
401/429 no-error-body parsing path remain unchanged. A retained status-only 400
does not retrospectively identify which parameter was rejected.

Generic HTTP diagnostics include the shared content-free rejection message hints
when code/param are null or absent. Fixed categories and parameter names can
identify an unsupported cache field without publishing the error message.

Measured 2026-10-19: the Luna-low subscription route rejected the explicit
breakpoint. Safe message hints classified `not_supported` and named the marker
and model. An accepted complete-message prewarm/appended-message test still
reported zero cached tokens, including the exact-repeat control. Public API
model-generation documentation is not route-specific capability evidence.

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

## Session affinity (opt-in)

The shared `InferenceSessionSpec` maps its effective cache group to
`prompt_cache_key`. Without a declaration, the wire request is unchanged.
`OpenAiSessionOptions(sessionAffinity: true)` additionally sends `session-id`
(effective affinity key) and `thread-id` (actual session identity).
`turnAffinity: true` requires both session affinity and a declared turn. It echoes
only the first valid server-issued `x-codex-turn-state` from a successful response
within that turn. These Codex conventions need qualification on the fixed SIWC
route; HTTP acceptance alone does not establish routing or cache benefit.

```dart
final request = const OpenAiSessionOptions(
  sessionAffinity: true,
  turnAffinity: true,
).attach(session.attach(existingRequest,
  turn: InferenceTurnSpec(id: logicalTurnId)));
```

Inject an `OpenAiSessionState` when provider clients are short-lived. Reconciliation
resets tokens on turn, model, cache group, affinity, auth owner/principal or local
signout epoch changes; late old-turn responses cannot overwrite the new turn.
Call `release(sessionId)` at session end and `clear()` when its owner is disposed.
The bounded default capacity is 32 active sessions; overflow refuses explicitly.
Tokens and principal identity stay in memory. This does not implement WebSocket
continuation, switch endpoints, borrow Codex credentials or add an actor loop.
