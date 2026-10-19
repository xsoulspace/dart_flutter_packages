# ADR 0067: Native ChatGPT plan inference is a provider, with host-owned context

Status: Accepted direction by operator; live account access observed, adoption pending
Date: 2026-10-13
North Star impact: applies

## Context

The operator authorized the native subscription delivery plan: Last Answer
signs in with ChatGPT and the harness supplies actor-specific context and actions
without invoking Codex CLI. Inference contracts and transports belong in DFP;
world policy and acceptance remain in ecsai_harness (ADR 0036).

The documented SIWC open-source/local preview permits direct OAuth Responses
requests. Eligibility of the actual application distribution and account needs
live evidence. A paid/remotely hosted distribution follows OpenAI's separate
registration route. Model catalog visibility is not proof of inference access.

## Options and decision

Retain codex exec/ACP as compatibility providers; app-server is a possible
embedded Codex runtime. Choose a native Responses provider for this plan because
the harness must own the decision loop, reconstructed context and action effects.
Do not add another agent scheduler or import Codex credentials.

`xsoulspace_inference_openai` owns public-client browser PKCE, validated OIDC
identity, registration-specific credentials, serialized refresh and revocation,
and stateless HTTP/SSE Responses transport. Applications supply protected
credential storage and a system-browser launcher. Keep this independent of the
Flutter/git-specific Universal Storage OAuth contracts; there is no justified
shared git/inference abstraction at this point.

The provider implements the existing inference/streaming contracts. It returns
tool requests and original Responses items; it never executes model actions.
Native call IDs and paired outputs are preserved by the provider codec. The
host owns the durable graph, privacy checks, current revisions and legal tools.
Opaque provider items are continuation artifacts, not another transcript owner.

The subscription profile uses public `/v1/responses`, `store:false`,
`stream:true`, explicit input and namespaced local function tools. Unsupported
generation controls refuse explicitly. Stream deltas do not establish success;
only a valid completed terminal response does. Interrupted or unknown effects
must not be replayed automatically. No API-key billing fallback is implicit.

## Consequences

Fresh requests can carry current raycast cuts without recursive transcript
compaction. Faithful tool/continuation reconstruction still needs host wiring and
behavioral qualification. Prompt caching cannot increase context capacity or
prove relevance. Existing CTX-3 filtering losses remain a separate adoption gate.

One auth owner serializes refresh for a credential store.
`RecoverableChatGptCredentialStore` optionally persists a mutation fence before
remote authorization exchange, refresh rotation or signout. Ordinary reads must
refuse pending mutations across a new auth owner; only explicit reauthorization
or signout may use retained credentials for recovery. Successful publication and
its cancellation rollback finish the fence. Remote uncertainty is not erased by
a locally successful recovery signout. Applications without this interface retain
only process-local publication quarantine and cannot claim restart safety. Protected storage and
cross-process access must be composed at the application/host boundary. Current
identity verification admits RS256 RSA keys of at least 2048 bits; an unqualified
algorithm refuses rather than weakening validation. The preview protocol may
change; fixtures are contract controls, not account eligibility evidence.

## Sources and qualification

Wire schemas use the shared core-to-JSON converter; the core's kind-tagged bundle
is not a wire schema. Explicit non-strict function/text formats retain optional
fields, with supported inline constructs validated locally and host action
validation retained. Unresolved references fail before dispatch. Conversion does
not preserve every primitive guide or constitute full JSON-Schema conformance.
HTTP diagnostic bodies are bounded and only numeric status plus fixed categories
and parameter families leave the provider; remote messages never do.

- [SIWC overview](https://developers.openai.com/siwc/token-sharing-open-source)
- [Registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts and rotation](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview restrictions](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Retrieved 2026-10-13. Package tests cover signed identity negatives, rotation,
late terminal failures, call correlation and native cancellation. Actual sign-in, account model discovery and a short direct request are observed
in Last Answer. Renewal, revocation, harness tasks and complete product journeys
remain separate required evidence in the harness native-subscription delivery ledger.

Recoverable stores persist cancellation intent before `cancelAuthorization`
acknowledges it. A normal finish must refuse cancelled intent; explicit rollback
finishes only after restoring local state and settling acquired-token cleanup.
Applications preserve unresolved remote-cleanup records independently from token
presence, and a failed recovery never clears the abandoned fence. Cancellation
requested but not durably acknowledged is not a crash-recovery receipt.

Optional settled structural receipts distinguish a provider's terminal output
from parsing and streamed deltas without retaining response content or IDs.
Only fixed output categories and nonnegative numeric usage leave this observer.
Observation is best effort and cannot change inference or grants; a quick
synchronous callback completes before the cast's physical settlement. This does
not imply settlement of shared authorization work.

Final streamed items follow the official
[output-item streaming contract](https://developers.openai.com/api/reference/resources/responses/streaming-events).
Retain indexed item-done originals, including encrypted reasoning, until a valid
completed terminal. Empty terminal output may reconstruct those final items;
nonempty output must agree. Gaps, conflicts and explicit noncompleted item states
refuse. No delta or item completion can bypass the terminal success gate.

## Declarative session/cache composition (2026-10-19)

North Star impact: applies. Shared core declarations separate session identity,
affinity key, authorized cache group and logical turn. They decorate the existing
request and context-boundary intent; they do not own transcripts, scheduling,
authority or source effects. No declaration preserves the prior wire defaults.
OpenRouter maps the declarations to session_id and prompt_cache_key; OpenAI maps
the cache group to prompt_cache_key and admits Codex-style session/turn headers
only through explicit typed adapter options. Public Codex source at commit
e4568a3538c9cab6627d64ff8cdfc7d98b79b7db informed lifecycle rules; its default ChatGPT
backend differs from this provider's fixed SIWC endpoint. Qualification remains
route-specific, and request acceptance does not establish cache benefit.

The OpenAI adapter may retain bounded in-memory state across short-lived clients.
It echoes a successful response's first server-issued turn token only within the
matching session, turn, model, cache group, affinity and auth-owner generation.
Late old-turn responses cannot rewrite a replaced turn. Caller release/disposal
and auth changes invalidate state. No token enters durable memory or raw logs.
Diagnostics retain allowlisted routing-header fingerprints and explicit missing
states, not backend identity or credential fingerprints. WebSocket continuation
and provider prewarm are separate capabilities, not implicitly added here.
