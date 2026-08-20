# Agent Harness Implementation Plan

> **Goal**: Build a general-purpose, UI-agnostic, cinematic (as abstration principle) multi-actor agent harness on ecsly.
> **Core thesis**: The harness is the intelligence amplifier. The model is a replaceable reasoning primitive.

---

## 0. Vision Summary

A living, multi-linear, game-like world where:

- **Actors** (LLM, human, or other) act, think, plan, research, use tools, and make decisions.
- **Projection** produces an extremely limited *Situation* (a "film cut") for each actor — only props in frame, only co-present actors, only the local question, explicit absences.
- **Agency** is granted only when a genuine `OpenDecision` exists. Everything else is mechanical (no LLM calls).
- **Threads** are first-class exploration branches. **Beats** are modality-agnostic content units (text, voice, tool calls, thoughts, observations).
- **Everything is an entity.** The graph is formed by typed reference components. Stories interlink. Multiplayer is natural.
- **The loop is continuous and idle-aware.** It sleeps when there is no work.

### The Loop (Concurrent, Non-Blocking)

```
Tick N:   Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch LLM calls, fire-and-forget) -> flush
Tick N+1: Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch new calls) -> ProcessResponses (process whatever arrived) -> Mechanical -> flush
Tick N+2: ... (same pattern, responses from Tick N may arrive here)
```

Key: `ActorAct` dispatches LLM calls concurrently and returns immediately. `ProcessResponses` processes whatever responses have arrived on this tick. The loop never blocks on a single LLM call. Multiple actors' LLM calls run concurrently. Idle/sleep only when no work remains.
