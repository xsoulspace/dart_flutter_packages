# xs_agent — interactive battle-test CLI

Daily-driver REPL over the agent harness + Apple Foundation Models. Every
session is a live bug hunt: races, projection quality, streaming, tool
reliability — all under real usage instead of synthetic tests.

## Run

```sh
cd pkgs/xsoulspace_inference_apple_foundation
dart run bin/agent.dart --root /tmp/agent_ws        # tool jail
dart run bin/agent.dart --trace                     # dump ledger every turn
dart run bin/agent.dart --no-debug                  # silence native traces
```

## REPL commands

| Command | Effect |
|---|---|
| `<text>` | Send as `OpenDecision`; response streams live; tools run in the jail |
| `_stats` | Channel watermarks (sent/consumed/dropped/cleared/buffered + invariant check), threads/beats/tokens |
| `_trace` | Dump `HarnessExecutionLedger` for the last turn (per-system durations + channel transitions) |
| `_save <path>` | Capture world snapshot to JSON (`ecsly_serialization`) |
| `_load <path>` | Read snapshot (full restore lands with Phase 8) |
| `_exit` | Stop loop, tear down |

## What to watch while battle-testing

- **Idle hangs** — if a turn never completes, `_trace` shows which channel
  still holds events. That's an idle-detection gap; file it with the trace.
- **Invariant violations** — `_stats` prints ⚠️ when
  `sent != consumed+dropped+cleared+buffered`. Data loss bug.
- **Projection drift** — long sessions: does the actor forget earlier context?
  Check beats/threads counts in `_stats`; truncation means budget pressure.
- **Streaming glitches** — duplicated or missing deltas point at
  `StreamingTapResource` / FFI bridge issues.
- **Tool reliability** — failed writes/reads appear as error results; check
  jail permissions first, then `toolExecutionSystem` timeouts.

## Ladder to production (Phases 5–6)

### Phase 5 — concurrency gating

AFM serializes requests on-device (~8s TTFT cold). Today
`AgencyPolicy.maxConcurrent: 1` in the CLI papers over it. To go multi-actor:

1. Add backend-declared max-in-flight to `Model` (e.g. `maxInFlight`), plumbed
   from the client (`AppleFoundationNativeClient` → 1).
2. `grantAgencySystem`: grant up to Σ(maxInFlight of resolved models), not a
   flat count. Queue the rest — they keep their `OpenDecision`.
3. Battle-test via CLI: spawn a second actor (`_spawn <prompt>` command — add
   when landing this phase) and watch `_stats` for queue depth and
   `dropped > 0`.

Storage note: no serialization work needed here.

### Phase 6/8 — session snapshot/restore

Goal: exit the CLI, come back tomorrow, continue the thread.

1. **Persist** (exists): `captureWorldSnapshot` captures entities carrying
   `PersistentId` + resources → JSON via `encodeWorldSnapshot`.
2. **Wire storage**: write snapshots through `universal_storage`
   (`StorageService` contract) instead of raw `File` — gets atomic writes +
   backend choice (filesystem now, cloud later) for free.
3. **Restore into a fresh world**: `decodeWorldSnapshot` → rebuild world
   (plugin order matters: AgentPlugin + SerializationPlugin before restore),
   re-spawn actors keyed by `PersistentId`, rebuild `FacetIndex` from restored
   beats (or verify it serializes — check `includeOnly` covers index inputs).
4. **Auto-save**: after each idle transition, debounced.
5. **Verify**: save mid-thread → restart → `_load` → ask "what did we just
   do?" — answer must reference pre-restart beats.

### After the ladder

- Hosted-model escalation tier (OpenRouter) behind the same router — CLI flag
  `--escalate`.
- 20-task suite run against real AFM through the same wiring the CLI uses
  (single handler path), closing the loop back to the pi comparison table.
