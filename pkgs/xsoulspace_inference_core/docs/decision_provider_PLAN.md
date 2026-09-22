# Optional decision providers — delivery plan

Updated: 2026-09-22. Forward work only; D0–D3 are outstanding. Documentation
records intended work, not implemented capability or model evidence.
`north_star_impact: applies`: extend provider-neutral inference contracts while
keeping product policy and all concrete providers outside core.

The consumer release is owned by the [harness PLAN](../../../../../ecsai_harness/pkgs/xsoulspace_agentic_harness/docs/agent/PLAN.md).
The boundary is [ADR 0038](../../../../../ecsai_harness/docs/decisions/0038_optional_decision_providers.md).
Cross-repository links assume the documented sibling checkout layout.
The separate [Jev pilot](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md)
is optional and cannot block the consumer release.

## Contract boundary

The generic capability evaluates bounded questions over a supplied state,
repeatedly for any compatible actor role. It does not emit arbitrary source
text, execute tools, grant consent, or certify acceptance. Successive choices
may select evidence, revise hypotheses, construct a plan, or compose a new
program through semantic operations materialized by the host. Whether a given
model performs those tasks usefully is an open empirical question, not a
routing-only restriction in the contract. The host owns candidate grounding,
state, execution, preconditions, permissions, completion, and fallback. Fully
resolved work bypasses inference; free-text generation stays a separate capability.

No mandatory methods are added to `InferenceClient`; existing implementations,
text/speech flows, and default behavior must remain compatible. No Jev names,
provider SDK imports, HTTP code, or harness dependencies enter inference core.
Registration occurs only in a consumer composition root. The existing baseline
works without any decision provider. Tasks explicitly bound to a removed
capability stop or rebind under declared policy; removal cannot silently erase
task state, claim completion or substitute an unauthorized provider.

## D0 — Minimal provider-neutral capability

Owner: `xsoulspace_inference_core`. Depends on ADR 0038 being accepted.

- Define a separate optional interface and typed request/result contracts for
  finite choice with abstention only. Defer boolean likelihood and ordinal
  rubric contracts until a concrete consumer requires them (for example a
  measured evidence-ranking experiment). Finite choice is the initial API,
  not a cognitive ceiling or a restriction on actor purpose. Names remain
  provisional until implementation review; do not force arbitrary JSON schemas
  through this capability or add provider-specific enum values to existing APIs.
- Declare supported question kinds, bounds, execution location/network needs,
  cancellation semantics, and unavailable/unsupported responses. Keep these
  capability facts separate from provider readiness and measured correctness.
- Carry an opaque request/cut identity, state revision, candidate-set identity,
  question version, and cancellation identity through completion. These are
  host-supplied values, not provider instructions or trusted provider echoes.
- Preserve per-option probabilities and separately identified confidence,
  resolved model/version, usage, and timing when supplied. Represent absent
  metadata explicitly; do not invent probabilities or calibration guarantees.
- Model abstention and unavailable outcomes explicitly. Choice sets include an
  escape option when non-exhaustive; empty or unsupported sets do not force a
  choice. Define cross-answer constraints as host validation, since questions
  may be evaluated independently rather than conditionally.

Gate: API compatibility fixtures with existing inference clients unchanged;
round-trip/value validation fixtures; `just check xsoulspace_inference_core`.
No provider registration or network is needed for these gates.

## D1 — Independent optional OpenRouter adapter

Owner: `xsoulspace_inference_openrouter`. Depends on D0.

- Add a separately constructed decision adapter and explicit import/entrypoint.
  The existing chat client and default exports must not silently activate it.
  Neither construction nor key presence registers it or triggers requests.
- Implement the documented System One endpoint with injected HTTP transport,
  configurable endpoint, exact model selection, bounded deadlines/retries, and
  cancellation/disposal. Do not change the chat client's endpoint or pretend a
  model string makes chat completions support decisions.
- Translate generic questions/results at the provider boundary; Jev wire names
  stay here. Unsupported features return typed failures before a network call.
- Host selection must filter local-only/network policy and allowed capabilities
  before ANY hosted request, including readiness probes, retries, shadow runs,
  and fallback. The adapter supplies truthful hosted/network capability facts.
- Preserve the selected/resolved model, cost when present, and opaque host
  correlation without logging keys or private state by default. Late responses
  after cancellation are discarded even if the server cannot abort computation.

Gate: injected transport contract tests and
`just check xsoulspace_inference_openrouter`; existing chat tests unchanged.
The [pilot contract sources](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md#sources)
are implementation references, not proof of account access or live behavior.

## D2 — Standalone package conformance

Owners: core/provider maintainers. Depends only on D0/D1. Tests are
deterministic and require no paid inference or harness implementation.
Harness J0 consumes D0–D2 and owns the separate integration proof below.

- Cover request limits, duplicate/unknown question IDs, missing/extra answers,
  type mismatches, invented choices, invalid distributions, non-finite/out-of-
  range values, and unknown metadata. Test the exact selected option against
  the original request's candidate set; never accept a response-created option.
- Cover auth/quota/rate limits, malformed/non-JSON errors, timeouts, bounded
  retry exhaustion, disposal, cancellation before dispatch and during flight,
  and a late successful answer after cancellation or revision change.
- Prove opaque host correlation survives transport and cancellation discards
  late answers. Provider-neutral fake consumers reject obsolete request/cut,
  candidate-set, and revision identities without importing harness code.
- Prove absent/unconstructed providers leave existing inference flows unchanged,
  require no credentials, and cause zero network requests. Fake consumers filter
  hosted capabilities for local-only mode before serialization or dispatch.

Gate: package checks above and standalone mock conformance fixtures.
Mock conformance is not a claim of Jev accuracy, latency, or workflow completion.

J0 integration handoff (not a D2 prerequisite): the real host must reject stale
answers, recheck preconditions/consent/acceptance, filter local-only policy
before every hosted probe/request/retry/fallback, retain zero model calls for
fully prepared actions, and prove provider absence/removal preserves baseline
behavior. Rejection or abstention uses bounded fallback or clarification.

## D3 — Versioned optional experiment and disposition

Owner: optional provider integration; Last Answer supplies representative coding
task fixtures. D3 supplies provider-owned evidence/dispositions within central
J1, independently for target selection (J1-T), evidence/hypothesis reasoning
(J1-R), unseen semantic coding (J1-C), and mixed actors (J1-M). Depends on D2,
J0 safety/host integration and frozen fixtures; J1-M additionally requires M0
and its working shared actor contract. Experiments may begin on a scripted or
disposable host before the full Last Answer release. D3 is not a prerequisite
of J0 or the consumer release. R/C exploration requires safety and operation
expressiveness, not T promotion or its cost/quality targets.

Run the bounded [Jev pilot plan](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md)
only with explicit provider/data/budget selection. Freeze question versions,
candidate generation, model versions, held-out examples, and promotion criteria
before evaluating. Freeze generic semantic grammars before held-out tasks;
do not hide task-specific solutions in candidate generation or prepared packs.
Report candidate coverage, task expressibility, decision quality, and complete
workflow success separately, with actor/candidate/materializer attribution.
Hosted shadow mode follows the same data policy
as active execution. No paid call is part of default package/CI checks.

Gate: a separate reproducible continue/keep-disabled/promote/remove disposition
per track with raw counts, supported-task repeated trials, cost, wall time,
fallback/abstention, failure examples, and non-claims. Negative and positive
findings are equally valid; no routing result proves coding, no coding sample
establishes broad coding capability, and no experiment auto-promotes a provider. Promotion
keeps the adapter optional and removable. Record completed evidence in a small
dated results record and remove completed instructions from this plan.
