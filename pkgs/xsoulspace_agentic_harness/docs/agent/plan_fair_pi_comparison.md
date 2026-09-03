# Plan — Fair pi vs harness comparison (Phase 4 follow-up)

Status: proposed. Binding context: ADR 0007 §3–4,
[results_phase4.md](archive/results_phase4.md). This is item **A1** in the living
[PLAN](PLAN.md) — it blocks every measured claim downstream, including A2's
tokens/task deltas (ADR 0009), because hosted columns cannot account tokens
honestly until C1 is fixed.

> Tier scope (ADR 0019): this suite is the **conventional tier** — short,
> single-session, mainstream-stack coding, the home turf of direct-grammar
> conversation agents. A fair loss here to a direct-grammar agent is expected
> and honest. The headline measurement is the **long-horizon tier**
> (multi-session, cross-task, repo-scale, snapshot/restore mid-run):
> [plan_long_horizon_tier.md](plan_long_horizon_tier.md) — that is the axis
> where the North Star claim (flat tokens/decision, persistence, multi-actor)
> actually binds and where the harness-vs-pi comparison is decisive.

Cross-reference: ADR 0009's falsifying experiment already showed the
plan-frontier mechanism removes the ReAct close-out call (−39% calls, −24%
tokens/task on scripted runs,
[results](results_plan_falsification.md)). Once this plan's matrix runs, add a
**mechanical-step share** column (work completed with zero LLM calls) to every
published table — it operationalizes the agency-discipline claim next to pass
rates.

## Investigation: why the current columns are not comparable

Three independent confounds, verified in code:

### C1. The OpenRouter client does not use the completion API properly

`openrouter_inference_client.dart` sends **one system message + one user
message** per call; the actor's projected context is appended as a trailing
`CONTEXT:` text block inside the user message. The code itself carries
`TODO(arenukvern): this is wrong - and should be rewritten to messages
(completion api)`.

Consequences for hosted models:

- No multi-turn `messages` array → no assistant/tool role history. Hosted
  models are trained on native chat-completion loops (assistant → tool_calls
  → tool result → assistant). Our client gives them a flattened single-shot
  prompt instead. Tool results reach the model only via the next call's
  re-projected context text.
- Token accounting is projection-based on both sides, so we cannot see how
  much context text this flattening wastes.

So yes — part of the hosted column's low pass rate (4/20) is likely the
_harness→backend input shape_, not model capability. Logged in
[`extensibility_ledger.md`](../../../../docs/decisions/extensibility_ledger.md).

### C2. The two harness columns don't even share a decision path

- AFM ran through `StructuredToolDecisionHandler`: every decision forced
  through a guided act-vs-answer schema; tool calls emitted as structured
  output.
- OpenRouter ran through `DefaultGenerationHandler` with **native tool
  calling**.

Two variables changed at once (model _and_ decision machinery). Neither
column isolates what we claim to measure.

### C3. There is no pi column — but it doesn't need ACP

ADR 0007 §3 assumed "pi driving the harness as an MCP/ACP server." That
inverts the integration and blocks on a server we never built (ledger entry).
pi itself exposes exactly what we need:

- **SDK**: `createAgentSession()` (`@earendil-works/pi-coding-agent`) drives
  the real agent loop headlessly — programmatic `session.prompt()`, event
  stream, in-memory sessions. This is pi-with-pi's-harness, which is the
  correct counterpart to our harness-with-our-loop.
- **OpenRouter is first-class**: pi ships an `openrouter` completions API
  variant (thinking format, session-affinity headers, provider routing) plus
  `registerProvider()` / models.json overrides if we need pinning.

The fair comparison is therefore **same model via OpenRouter, two harnesses**:
our ECS loop vs pi's agent loop, each driving its native decision machinery
over the same tasks/workspaces/checkers. Comparing "harness+AFM" against
"pi+hosted" was never meaningful anyway (different models AND different
harnesses); the interesting axes are:

| Axis                                   | Question answered                        |
| -------------------------------------- | ---------------------------------------- |
| harness(AFM) vs harness(OR:same-model) | model swap under our harness             |
| harness(OR:m) vs pi(OR:m)              | harness swap under same model ← headline |
| harness(OR:m) pre/post C1 fix          | how much the flat prompt shape costs     |

## Plan

### Step 1 — Fix the OpenRouter client to real chat-completions shape (C1)

Scope: `xsoulspace_inference_openrouter` only; no core change.

Design ruling (per ADR 0007 seams + North Star "memory is a re-derivable
projection"): the `messages` array is a **codec, not state**. It is computed
fresh per call by rendering the budgeted `Situation` — never stored, never
appended to. Conversation-log agents accumulate messages; we serialize beats:

| Role                       | Rendered from                                                |
| -------------------------- | ------------------------------------------------------------ |
| `system`                   | `ActorSystemPrompt` + goal vector + plan frontier (ADR 0009) |
| `user`                     | user-input beats addressed to the actor                      |
| `assistant` / `tool_calls` | actor's text/thought beats, tool-call beats                  |
| `tool`                     | tool-result beats, kept atomically paired to their calls     |

Constraints the renderer must respect (recorded so nobody simplifies them
into silent truncation):

- **Pairing atomicity** — chat APIs validate `tool_calls` ↔ `tool` result
  pairs; a pair is never split across the budget boundary. Recent turns render
  verbatim; older material collapses into a leading synthesized context block
  (keyword-ray hits + reduction beats).
- **Budget inheritance** — rendered message tokens count against the same
  enforced budget as today's `CONTEXT:` text; the long-horizon flatness gate
  asserts on rendered output, so linear replay cannot sneak back in.
- **One projection, many codecs** — AFM guided-schema and OpenRouter native
  tools become two renderers over the identical `Situation`. This is also the
  principled resolution of C2: cross-backend comparisons share the cut and
  differ only in encoding.
- **No cached transcripts** — if prompt-prefix caching is exploited later,
  the cache is derived-and-rebuildable (facet-index discipline, Phase 6).
  Projection is already deterministic (injected tick), so prefix stability is
  reachable WITHOUT distorting the cut. Do not reorder or duplicate content
  for cache hits before the fair baseline exists — record `cache_hit_rate`
  as a future metric column instead.

Practical scope:

- Build the `messages` array from projected beats instead of concatenating a
  trailing `CONTEXT:` block.
- Keep the current single-shot path behind a flag initially so we can run the
  A/B (axis 3 above) without losing the baseline.
- Record real usage from `decoded['usage']` into response meta; surface it in
  traces so tokens/task stops being projection-only for hosted backends.
- Validate: rerun the OR suite; compare pass rate + tokens/task against
  `runs/openrouter_run.jsonl`. This delta is itself a publishable finding.

### Step 2 — Unify the harness decision path across backends (C2)

With the Step 1 codec design, backends share one `Situation` and differ only
in the renderer — so "decision path" reduces to a per-backend renderer choice
plus its output grammar (guided schema vs native tool calls), both driven by
the same cut. What remains to pin empirically:

- Run each backend through **both** wrappers once (guided-decision AND native
  tools), or pick one per a small pilot (3 tasks × 2 wrappers × 2 backends)
  and stamp the choice into the trace rows. Minimum bar: every published
  column states which decision path it used, and cross-backend comparisons
  use the same one.

### Step 3 — Build the pi driver (C3)

New tool (TS, lives outside `pkgs/`, e.g. `benchmark/pi_driver/` — no core
changes):

- Node script using `createAgentSession()` + `ModelRuntime`, cwd = per-task
  sandbox dir seeded by the same fixture builder the Dart runner uses.
- Model pinned to the identical OpenRouter model id used by the harness
  column; API key from the same EnvConfig store (dumped to env for the child
  process).
- One `session.prompt(<task instruction>)` per task — the task YAML prompt
  verbatim. No skills/extensions loaded beyond the stock toolset, so pi runs
  its native loop.
- Extract result by running the existing deterministic checkers: add a tiny
  Dart CLI (`check_workspace.dart`) that loads task YAML + checks the sandbox
  dir — checker semantics stay single-sourced in Dart, the TS driver just
  invokes it.
- Emit the same JSONL row schema (`task_id`, `passed`, `wall_clock_ms`,
  `tool_calls`, `failure_mode`, …) with `backend: "pi"`. pi reports real
  token usage per request — capture it from the SDK events. **Assert usage is
  non-null in the driver and fail loudly if absent** — a silent fallback to
  projection-based accounting would reintroduce the exact confound this plan
  fixes (C1).
- Retry policy parity: our suite feeds failed checkers back up to
  `--retries 2`. Give pi the equivalent budget: on checker failure, send one
  follow-up prompt with the checker detail, max 2 feedback rounds. Same
  information, same budget.

### Step 4 — Tool-surface parity statement (do not over-engineer)

Our jailed fs tools (`read`/`write`/`list_dir`) vs pi's stock tools
(read/edit/bash/glob/grep) differ. Two options, decided before running:

- **Preferred:** restrict pi to read/write/ls-equivalent tools via an
  extension that filters the tool list (extensions can intercept tools), so
  both agents get the same action vocabulary.
- Fallback: leave pi's full toolset and label the column
  "pi + full toolset" — still valid for the harness-comparison claim, but the
  tool axis must be stated next to the number.

Do NOT port our tools into pi or vice versa — the tools are part of each
harness's normal operating condition; parity of _capability class_ (read,
write, list/search) is the requirement, not byte-identical schemas.

### Step 5 — Run matrix + publish

| Column      | Backend                                      | Decision path    | Tokens source            | Mech-share                              |
| ----------- | -------------------------------------------- | ---------------- | ------------------------ | --------------------------------------- |
| harness+AFM | apple-foundation                             | unified (Step 2) | projection (only option) | yes                                     |
| harness+OR  | dots-3-note-preview:free (or paid tier twin) | unified (Step 2) | real usage post-C1       | yes                                     |
| pi+OR       | same model id                                | pi native        | real usage               | n/a (report pi tool-call count instead) |

Publish an updated `results_phase4.md` (or `results_comparison.md`) with all
axes, the C1 A/B delta, and explicit labels. Free-tier model ids can silently
reroute/deprecate — pin the model id and record the date; prefer a paid
equivalent if free-tier instability corrupts the comparison.

## Non-goals / guardrails

- No MCP/ACP server in this plan — the SDK route removes the blocker; the
  ledger gap entry stays until/unless a server is genuinely needed for
  another purpose.
- **No MCP anywhere** — `dart_mcp` would only matter for exposing tools over
  a protocol; Step 3 bypasses protocols entirely (`createAgentSession()`
  direct, checkers invoked outside the agent).
- **No mcp_flutter** — it inspects running Flutter apps; unrelated to
  headless agent-loop benchmarking.
- **`xsoulspace_inference_acp` excluded from this matrix** — driving pi as an
  ACP backend would measure "our harness + pi-as-model", not pi's native loop
  (reintroduces the C2/C3 confound). It also can't report token usage or
  tool-call counts today (meta carries only `sessionId`/`stopReason`).
  Recorded as a _future_ candidate for a clearly-labeled
  "hosted-agent-as-backend" exploratory column once it surfaces usage.
- No core changes: Steps 1, 3, 4 live entirely in provider/driver packages;
  Step 2 is benchmark-code only.
- Failures remain data: pi's failures get the same failure-mode treatment,
  not a gentler narrative.
- If A2 (goals/plans, ADR 0009) lands before the matrix run, stamp each row
  with `plan_frontier: on/off` — otherwise the −24% tokens/task from close-out
  elimination would silently confound the harness-vs-pi comparison.

## Sequencing

1 (C1 fix + A/B) → 2 (pilot, pick decision path) → 4 (decide tool parity) →
3 (pi driver) → 5 (matrix run + doc). Estimated: Step 1 ~half a day incl.
validation run; Step 3 ~a day; rest small.
