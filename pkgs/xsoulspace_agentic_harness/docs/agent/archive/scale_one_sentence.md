# Scaling one sentence into a full prototype — diagnostics & composition

> Empirical notes (2026-08-27) from running the stack against the initial goal
> (AFM + real coding tasks) and from the harness + AE composition demo.
> All claims measured, not asserted. Failures are data.

## What "profile each piece" shows (per-phase cost)

The faithful, non-tuned profiler is the attribution ledger (`harness_profile`)
wrapped over the real loop; hand-driving schedules to time phases is the
documented footgun (idle-race class) and we removed a too-fragile manual
stepper rather than ship a wrong clock.

Scripted 20-task suite, LLM-free, whole loop:

- **decisions:** 282 (that's 282 model grants)
- **context buckets (bytes):** system=84,911 · prompt=115,337 · generated=1,128 ·
  absence/assistant on top; **context (projection) ~39,450**
- **tokens/decision stay flat** and the projection never exceeds its budget —
  the bounded-memory claim holds on the real loop.

All 282 decisions `answered`; end everyone `expectIdle`-clean.

## Real-model run (AFM, macOS, on-device) — the initial goal

Ran the discovery-heavy slice (4 `search_*` tasks) natively over Apple
Foundation Models:

| task | pass | used tools | why |
|---|---|---|---|
| `search_04_dead_code` | ✅ | read, rename_symbol_multi | located + applied cross-file rename cleanly |
| `search_01_find_and_fix` | ❌ | - | wrote wrong content (wrong-edit) |
| `search_02_which_file_uses_api` | ❌ | glob, read, patch/rename | **misused `rename_symbol_multi`**: a declaration renamer, applied where a call-site edit was needed |
| `search_03_count_and_report` | ❌ | - | content mismatch (1 char vs expected) |

Findings worth being honest about:
- **Discovery tools are being picked up** — the model reaches for `glob`/`read`
  now that they exist; `search_02` used them.
- **The residual is P1 edit-quality, not decision machinery nor discovery.**
  `search_02` narrowed the call site via `read`, but asked the wrong tool
  (`rename_symbol_multi` renames a *declaration*; this needed a call-site patch)
  and the tool correctly refused (`symbol_not_found`, declared file). That's a
  *tool-selection / task-formulation* gap — the harness left everything,
  including the refusal teaching the shape, correct.
- Separate from leave-with-ones: transient AFM generation errors classified as
  `transient-errors`; the retry bounded them, no hang, no idle-race leakage.

**No harness bug surfaced.** The pieces (projection budget, floor tokens,
discovery tools, tool-contract refusals, retries, idle detection) all behaved.

## "Scale one sentence into a whole prototype" — the composition

`bin/prototype_from_sentence.dart` is the proof. It composes what we built with
zero core changes:

```text
  "a bookmark manager that saves the current URL and lists saved ones"
   │  1. host → FlowSpec: declarative loop (stages + tool surface + archetype)
   │  2. world → AgentWorldSetup + HarnessLoop (embedding surface)
   │  3. jail + discovery tools (grep/glob) — the agent works there
   │  4. verify gate → DatasetSpec tier (passable vs evidence)
   ▼
   prototype workspace + verdict row
```

Runs LLM-free (scripted) in milliseconds; swap the handler for AFM/OpenRouter
to "vibe" the real thing. Tiers the outcome (store = passable, README =
evidence), so we never over-claim a draft.

## Why this composes (the ADR 0014/0015 thread)

- **Coding is a domain; dialogue/screenplay/book is a domain; the core is
  neither.** `last_answer` owns conversation document types + ACP; a host
  embeds the harness via `AgentWorldSetup`+`HarnessLoop`+`DecisionFlow`+tools.
- **AE (`agentic_executables`) is world-affordance** (verify_pack, canonical
  packs as `See`-seam tools), never the actor's memory.
- **Embedded vs ACP is a host decision**: in-process, low-latency, shared-memory
  conversation → embedded; general/parallel/cross-process → ACP.
- **Progression:** one sentence → a `FlowSpec` loop → a jailed world → discovery
  tools → a produced workspace → tiered verdict; the same seams scale to a real
  repo, a real product, and (via AE) truth-hold against a spec.