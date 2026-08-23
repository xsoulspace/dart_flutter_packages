# ADR 0008: EnvConfig — global/local environment configuration store

- Status: Accepted
- Date: 2026-08-26
- North Star impact: `clarifies`
- Builds on: [0007](0007_extensibility_seams_and_conformance.md) (CLI/backends are platform consumers)

## Context

The agentic CLI surface is growing (`coding_suite_afm.dart`,
`coding_suite_openrouter.dart`, future backends), and every backend needs the
same secrets/settings plumbing: API keys, default models. Today each bin
reaches for `Platform.environment` only, which forces users to export keys in
every shell or repeat `--api-key` on every invocation. Every established CLI
coding agent solves this with two-scope persisted config plus process-env
override.

## Decision

1. **Two file scopes + process env, fixed precedence**:
   `process env → local (.xsoulspace/config.json) → global
   (~/.config/xsoulspace/inference/config.json, XDG-aware) → null`.
   The Unix contract (`KEY=x cmd` overrides everything) is non-negotiable.
2. **Flat JSON string map only.** This is an *env store*, not a settings
   tree. Nested tool config belongs to the tool layer. No dotenv format —
   zero dependencies, and `.env` compat can be layered later as a loader.
3. **Corrupt files degrade, never throw.** A malformed config prints a
   warning and reads as empty; the next `set()` overwrites it. Broken config
   must not brick a CLI.
4. **Plaintext values.** Same tradeoff as every dotenv/coding-agent config;
   documented rather than hidden behind half-encryption.
5. **Pure Dart, no deps** — lives in `xsoulspace_inference_core/lib/src/config/`,
   usable by all bins and hosts.

## Non-goals

- Secret encryption / OS keychain integration (possible follow-up, per-OS).
- Nested schemas, validation, migrations — tool-layer concerns.
- Writing to process env.

## Consequences

- Bins resolve credentials uniformly: flag → env var → saved config, with an
  actionable error naming the exact file paths when unset.
- Users gitignore `./.xsoulspace/` at their own discretion (documented).
- If a third scope or hierarchical merge is ever needed, this is an
  `amends`-class change requiring a new ADR.
