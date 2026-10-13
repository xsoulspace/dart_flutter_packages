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
allowlisted nonnegative numeric usage. It carries no text, arguments, IDs or
credentials. Observer exceptions cannot alter inference; keep this synchronous
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
