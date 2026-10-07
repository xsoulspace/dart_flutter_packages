# Changelog

## 0.1.0

- `LayaServeRuntime`: attach-or-spawn lifecycle for a local laya-serve
  endpoint with health polling and early-exit detection; attach-only by
  default, kills only spawned processes.
- `LayaLocalDecisionProvider`: `DecisionProvider` with honest local
  capability facts (`local` / `none`), composing the shared System One wire
  adapter; detached runtime surfaces as typed `DecisionUnavailable`.
