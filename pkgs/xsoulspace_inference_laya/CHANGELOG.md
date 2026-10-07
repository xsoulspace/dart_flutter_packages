# Changelog

## 0.1.0

- `LayaServeRuntime`: attach-or-spawn lifecycle for a local laya-serve
  endpoint with health polling and early-exit detection; attach-only by
  default, kills only spawned processes.
- `LayaLocalDecisionProvider`: `DecisionProvider` with honest local
  capability facts (`local` / `none`), composing the shared System One wire
  adapter; detached runtime surfaces as typed `DecisionUnavailable`.
- `LayaDecisionServer`: a laya-compatible System One wire server in pure
  Dart (`/health` + `/v1/systemone`, optional bearer auth) with a pluggable
  `LayaDecisionEngine` seam and `ScriptedLayaDecisionEngine` — the whole
  decision path runs and is tested with no Python and no model weights.
