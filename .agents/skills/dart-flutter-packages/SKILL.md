---
name: dart-flutter-packages
description: Use when editing, validating, or diagnosing packages in the dart_flutter_packages monorepo. The agentic harness product lives in ~/xs/ecsai_harness and is not maintained from this skill.
---

# dart_flutter_packages working guide

[Root AGENTS.md](../../../AGENTS.md) is the entrypoint. Read the affected
package's `AGENTS.md` before editing. Skill Steward owns the operational map.

The agentic harness product (engine, host, workspace, AFM composition) is
`~/xs/ecsai_harness`. Inference packages and shared contracts stay here.
Do not reintroduce a dependency from a provider package onto the harness.

## Validation

From the repository root, name the package. The Justfile defaults to
`xsoulspace_inference_core` when the argument is omitted.

```bash
just check xsoulspace_inference_core
just analyze-one <package>
just test-one <package>
```

Record a baseline before editing a package that already has failing tests.
Do not treat a pre-existing failure as permission to add another.

## Conventions

- `steward map` shows the operational desk. Package gates are
  `steward action <pkg>.analyze` and `steward action <pkg>.test`.
- Classify `north_star_impact` before a durable structural change.
  `amends` / `conflicts` need an ADR first.
- Provider packages implement `InferenceClient`. They do not host daemon,
  runner, or ACP policy.
