---
description: Onboard to a package in the dart_flutter_packages monorepo
argument-hint: "<package>"
---
Onboard me to the package `$1` (default: xsoulspace_inference_core if omitted) in this monorepo. Do the following, in order, and summarize concisely at the end:

1. Read the root `AGENTS.md` and `pkgs/$1/AGENTS.md` (if present). Note any working agreements or guardrails.
2. Run `steward doctor --json` and report anything unhealthy.
3. If it's `xsoulspace_inference_core`, read `pkgs/xsoulspace_inference_core/docs/agent/architecture.mdx` and list `pkgs/xsoulspace_inference_core/example/lib/headless/`.
4. Validate the package scoped (use the `workspace_check` tool with action `analyze`, then `test`).
5. If tests fail, use `test_baseline_record` so pre-existing failures don't block future work, and list them as known-failing.

Finish with: purpose of the package in one sentence, its validation commands, known-failing test count, and the top 3 files a new agent should read before editing.
