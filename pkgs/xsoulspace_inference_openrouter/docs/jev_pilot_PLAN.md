# Jev pilot — optional experiments

Updated: 2026-09-22. All tracks outstanding; no live evidence exists for this
integration. Default: disabled and removable without losing baseline behavior.
Experiments are not consumer release dependencies and never run in default CI.

Provider work is [D0–D3](../../xsoulspace_inference_core/docs/decision_provider_PLAN.md).
Host ownership and J0/J1/M0 are in the [central PLAN](../../../../../ecsai_harness/pkgs/xsoulspace_agentic_harness/docs/agent/PLAN.md).
Each track needs D2 conformance, J0 safety/integration, frozen fixtures, and an
expressive enough host surface. J1-M additionally needs M0 and a working shared
actor contract. A scripted/disposable host is sufficient to begin; the full
Last Answer release is not a prerequisite. R/C exploration does not depend on
T quality promotion or its latency/cost result. Stop on host safety failures.

## Hypothesis and boundary

Jev cannot emit arbitrary source strings. It may nevertheless select evidence,
revise hypotheses, and synthesize a previously unseen program through repeated
semantic operations. The host emits source, preserves typed artifact invariants,
and executes tools. This is a testable hypothesis, not an established capability
or a routing-only limitation. A finite-choice API can test it without adding
Scores; introduce a generic rubric capability only when a concrete ranking
experiment requires it. A rubric score is not an arbitrary numeric value slot.

The host owns cut/revision/candidate identities, preconditions, permissions,
acceptance, budgets, and effect application. No model confidence grants consent
or certifies completion. Fully resolved work uses zero model calls. Include
abstention, insufficient evidence, unsupported operation, and missing-value
outcomes instead of forcing the nearest choice. Local-only policy filters
hosted calls before serialization/dispatch, including probes, retries, shadow
runs, fallback, and any generative candidate proposer.

Use the documented OpenRouter System One endpoint with a versioned model:
`POST https://openrouter.ai/api/v1/systemone`. Current docs map `jev-1.13` to
`typesafe/jev-1.13`; responses identify the resolved snapshot. Confirm the pinned
route and record resolution before measurements; a changed snapshot invalidates
comparability. Do not use `jev-latest` for evidence. The alpha Decisions endpoint
is an alternative contract, not a required second implementation path.

Questions within one Jev call are independent. Dependent reasoning/composition
uses successive calls with updated state; the host validates any cross-answer
constraints. Confidence and winning probability are separate signals, neither
an individual correctness guarantee. Tune thresholds only on development data.

## Common method and attribution

Freeze fixtures, generic operation grammar/materializers, candidate generation,
question versions, model snapshots, splits, seeds/order, deadlines, acceptance,
and limits before held-out runs. Last Answer fixtures represent coding requests
through the existing AgentDoc path; no new app-document adapter is required.
Use synthetic or explicitly authorized redacted inputs.

Compare Jev, AFM, and a hosted generative model through the SAME finite action
interface, cuts, candidates, feedback, and per-run limits. Include deterministic
host-only and seeded random-choice ablations. An unconstrained generative coding
baseline is a separate practical comparison outside the production mutation
route: report its larger action space, not a model-only attribution. Availability
failures remain reported outcomes.

No complete-solution options, task-specific prepacked patches, hidden reference
answers, or hidden acceptance-test leakage. Use held-out operation combinations
and task families where feasible, beyond merely changing names. Freeze generic
candidate construction before held-out tasks. Literal values come from explicit
request/source values or a declared generic bounded domain; missing values are
an expressiveness limit. Any generative candidate proposer creates a separately
labeled mixed arm, with all its calls/cost included; it cannot be concealed in a
Jev-only run. Disclose host heuristics that order, prune, or resolve alternatives.

Record per decision: task/attempt/actor/role, request/cut/state revision,
candidate-set and question versions, candidate/proposal author, hypothesis
origin, selected operation and ordering, literal/reference provenance,
materializer version, model snapshot, probability/confidence, feedback, repair,
fallback, deadline, tokens, cost, and wall time. Record task expressibility and
candidate coverage separately from reasoning failures. Keep host-only material-
ization distinct from semantic solution authorship. Report every scheduled run:
passed, failed, abstained, unavailable, timed out, budget-stopped, or not started.
Never drop incomplete outcomes to improve success rates.

## J1-T — Target selection

Select an ambiguous workspace symbol, Markdown anchor, or configuration key from
host-grounded candidates. This establishes bounded selection evidence only.

- 160 unique examples maximum: 60 development, 100 held out. Include similar
  names, absent/omitted targets, multilingual or multi-target requests, stale
  state, and instruction-bearing content. Replay deterministic matches apart
  from genuine ambiguity; never insert inference into those execution paths.
- Report four operational arms: deterministic-only, current generative baseline,
  Jev-only, Jev plus existing fallback. AFM and random ablations follow the common
  method. Reuse raw first-stage Jev results across the two Jev arms; physical
  calls count once, each logical arm includes that stage's cost and latency.
- Ceiling: 600 inference calls total (including native, proposer, fallback,
  retries), USD 5 hosted, 30 minutes live wall time; whichever first. One
  selection per attempt, at most one fallback and one transient retry per
  stage, 30 seconds per example/arm. All consume the global ceiling.

T's proposed opt-in target-selection gate: all safety fixtures pass, zero wrong
accepted selections in 100 held-out cases, at least 30 correct ambiguity
resolutions without fallback, no workflow-success loss against baseline, and
at least 20% total hosted cost or end-to-end p95 improvement with no more than
10% regression in the other metric. Insufficient eligible cases or exhausted
budget is incomplete evidence. Report accepted counts and statistical limits;
zero observed errors is not proof of safety. These thresholds apply only to T,
not permission to explore R/C or claims about coding.

## J1-R — Evidence and hypothesis reasoning

Choose the next evidence read, distinguish competing host-represented
hypotheses, revise after observations, and select a next diagnostic step. Use
cases requiring a dependency between observations, not independent labels only.
Generic hypothesis descriptions must not contain a hidden task-specific repair.

R/C share at most 20 unique tasks: 8 development and 12 held out. On each
held-out task schedule three fresh isolated trials per tested arm, with reset
state and counterbalanced candidate order. Target 3–8 meaningful choices; R has
at most 12 total choices per task/arm/trial. At most one transient transport
retry per choice; no task-level restart disguised as a retry. Each trial has a
three-minute deadline. Count attempted and rejected choices toward the cap.

Gate: report evidence-selection accuracy, hypothesis revision after contrary
evidence, information insufficiency, supported-task repeat success, and host/
random/AFM/generative comparisons. A model-selected diagnostic trace is evidence
of this bounded reasoning behavior only. No routing promotion threshold applies.

## J1-C — Unseen semantic coding

On the shared tasks, compose new behavior through generic typed operations:
select targets/references, expression/operator alternatives, declared literals,
and operation ordering; inspect task-visible verification feedback and repair.
The exact resulting operation sequence must be unseen, not a retrieved whole
solution. Keep independent hidden acceptance separate from available feedback.

Use three fresh held-out trials per task/arm as above. Target 3–8 choices;
maximum 16 total choices and one transient retry per choice, at most two
candidate materialization/verification attempts, three minutes per trial.
Repairs, evidence requests, and terminal decisions all consume the choice cap.
Unsupported operations or missing literal values are reported rather than
quietly adding a task-specific materializer after seeing the answer.

R+C combined ceiling: 2,400 inference calls including native, proposer, retries,
and fallback; USD 20 hosted; 120 minutes live wall time, whichever first.
Pre-register a balanced arm/trial schedule before running. This ceiling may
truncate the full matrix: preserve partial counts and do not claim repeated
coverage for unfinished cells. A later expanded run requires its own budget.

Gate: publish per supported task all three trial outcomes, independent acceptance
and regression results, complete artifact/trace, unsupported coverage, and
comparison/ablation counts. Label a task reliably demonstrated in this sample
only if all three trials pass without hidden outside authoring; failures remain
in aggregate results. A positive or negative result answers this bounded
composition hypothesis. It neither proves general coding ability nor enables
production automatically. Cost/latency are measured, not prerequisites to
investigate capability.

## J1-M — Mixed actors

Depends on M0 and the working shared actor contract, plus safety and
expressiveness evidence for the participating roles. No prior model-quality
promotion is required. Compare explicit role assignments: Jev evidence/semantic
composer with AFM or hosted prose/escalation; generative proposal with Jev
selection; and the strongest single-provider actor baseline. Preserve common
host state, policy, and artifact ownership. Each role has its own capability
requirements and fallback; no Jev import enters the host/core to make this work.

Use at most 8 of the frozen held-out tasks, three isolated trials per tested
configuration. No new task-specific options or packs. Maximum 16 choices,
two materialization/verification attempts, one transient retry per choice,
and three minutes per task/configuration/trial. Track ceiling: 800 inference
calls across all actors/providers, USD 10 hosted, 60 minutes, whichever first.
Every actor/proposer/fallback call counts; report an incomplete matrix honestly.

Gate: report role-level authoring/decision attribution, cross-actor state and
cancellation correctness, supported-task repeated acceptance, and actual
quality/cost/latency against the single-provider baseline. A mixed success is
not a Jev-only coding result. Continue, retain disabled, or remove per measured
role; topology complexity needs a demonstrated benefit.

## Budget enforcement and disposition

Track budgets are separate ceilings, not targets or inferred permission to
spend. Explicit provider/data/budget opt-in is required; smaller approved limits
prevail. There is no automatic budget increase. Before a hosted call reserve a
conservative worst-case charge from declared current pricing and permitted
input/output/other billable-unit maxima, including retries/fallback. Retain the
reservation if returned cost is unknown and label actual cost unknown. Without
a reliable bound stop before dispatch. Never count unknown cost as zero.

Record source/version of prices, physical call counts, logical-arm attribution,
reported versus conservatively charged cost, end-to-end wall time, and missing
metadata. Include failed calls and baseline/proposer work. Provider-only latency
is insufficient. Never log keys or private state by default.

Publish a separate continue/keep-disabled/promote/remove disposition per track.
Both positive and negative findings are useful. No track automatically promotes
another. Any opt-in consumer cohort needs its own supported-role acceptance;
wider rollout requires separately scoped evidence. Keep the provider optional,
removable, and out of the main harness's mandatory dependency path.

## Sources

Primary documentation checked 2026-09-22; recheck before implementation:

- [OpenRouter System One contract](https://openrouter.ai/docs/guides/community/typesafe-sdk): endpoint, model mapping, wire shapes.
- [OpenRouter alpha Decisions OpenAPI](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request.md): alternative contract.
- [TypeSafe System One](https://docs.typesafe.ai/concepts/system-one): typed outputs, text-only inputs, calibration limits.
- [TypeSafe coding-agent guidance](https://docs.typesafe.ai/introduction/coding-agents): not a drop-in chat/code-completion model; does not evaluate host-mediated semantic synthesis.
- [TypeSafe Choice](https://docs.typesafe.ai/primitives/choice) and [hierarchical search](https://docs.typesafe.ai/cookbooks/hierarchical_classification): finite options and successive choices/beam search; not coding evidence.
- [TypeSafe Score](https://docs.typesafe.ai/primitives/score): rubric positions, not arbitrary numeric generation.
- [Confidence](https://docs.typesafe.ai/confidence) and [independent questions](https://docs.typesafe.ai/introduction): probability/confidence semantics and host composition.
- [Launch evaluation](https://typesafe.ai/blog/introducing-system-one-models-and-jev): evaluates supplied workflows, not novel code synthesis.

The proposed semantic-coding interpretation is a hypothesis from the interface,
not a vendor result. Documentation proves neither account access nor measured
latency, accuracy, data-policy compatibility, or Last Answer acceptance.
