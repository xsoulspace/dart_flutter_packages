# Concept Graph Architecture Proposal

Status: proposal
Branch: `codex/concept-graph-architecture-doc`

## Executive Summary

The current repository is locally reasonable but globally inefficient. Packages,
interfaces, adapters, wrappers, generated SDK bindings, registry metadata, and
validation gates all make sense in isolation. At repository scale, they become
hard to reason about because the primary authoring unit is the package, while
the real design unit is the concept.

The proposed direction is:

```text
concept graph -> source modules -> materialized packages -> registry artifacts -> validation graph
```

Packages should remain real Dart packages for now. Dart, pub, analyzers, IDEs,
and the registry all need materialized package directories with `pubspec.yaml`
and real files. The change is not to erase packages. The change is to build a
concept layer above them so the team can ask and change code by purpose:

- "What implements `platform.ads`?"
- "Which packages implement speech-to-text?"
- "What breaks if `xsoulspace_platform_core_interface` changes?"
- "Which generated SDK wrappers feed platform adapters?"
- "Run only the checks for `storage.cloudkit` and its impact set."

The architecture should start as a read-only graph overlay, then grow into
conformance rules, contract tests, selective generation, and finally projected
release packages.

## MoE Discussion Summary

### Concept Graph Lens

A concept graph fits the repository, but only as an overlay on top of package
and pubspec reality. It should index existing packages, exports, imports,
tests, generator locks, readiness status, registry metadata, and public
surfaces. It should not become a second package manager.

The graph must support multi-membership. For example,
`xsoulspace_platform_crazygames_ads` belongs to platform, ads monetization,
CrazyGames JS, and optional plugin concepts at the same time. Prefix grouping
is only a seed.

### Package Projection Lens

Virtual packages are risky in Dart. A package must eventually become an
inspectable directory or archive with a `pubspec.yaml`, files, and publishable
bytes. The safer model is materialized projections:

- Keep `pkgs/*` as the authoring truth at first.
- Generate release-ready copies into `build/projected_pkgs/<package>/`.
- Include provenance such as `.projection.json`.
- Let the registry build archives from projected packages only after this is
  proven on a small subset.

Pub workspaces are useful but should be a later experiment. They require a root
`pubspec.yaml`, workspace member resolution, Dart SDK constraints compatible
with workspace resolution, and one shared lock/config. That is a large behavior
change for this repository.

Reference: [Dart pub workspaces](https://dart.dev/tools/pub/workspaces).

### Generation And Codemod Lens

The goal is not "generate everything." The goal is:

```text
generate boring shells, lock upstream surfaces, codemod repeated scaffolding,
preserve handwritten semantic adapters
```

Good generation targets:

- native loader specs
- JS SDK raw bindings and snapshots
- platform adapter shells
- package metadata projections
- README/export/package boilerplate
- reusable contract test suites

Bad generation targets:

- high-level wrapper semantics inferred only from TypeScript
- platform-specific behavior with product judgment
- capability bodies where behavior is not yet stable
- full package creation ahead of real usage

Reference: [OpenRewrite recipes](https://docs.openrewrite.org/concepts-and-explanations/recipes).

### Rollout And Validation Lens

The new system must not become heavier than the package sprawl it replaces.
Start with thin read-only tooling and fast kill criteria. Promote behavior only
after it proves value on real vertical flows.

The first success condition should be boring: a graph report answers useful
impact questions faster than prefix search, with evidence paths and confidence.

## Current Repository Signals

The repository already contains seeds of this architecture:

- `registry/tools/_registry_workspace.dart` discovers `pkgs/*/pubspec.yaml`
  and normalizes package metadata.
- `registry/tools/build_registry_index.dart` creates registry metadata,
  archive hashes, pubspec payloads, and release manifests.
- `tool/xsoulspace_production_readiness.dart` models package status, checks,
  scope, exclusions, and blocking state.
- `pkgs/xsoulspace_platform_foundation` has a real runtime around
  `PlatformRuntime`, `PlatformAdapterFactory`, `PlatformClient`, and
  `PlatformCapability`.
- `pkgs/xsoulspace_js_interop_codegen` already centralizes parser, snapshot,
  source adapter, hash, and file generation helpers.
- `tool/platform_sdk_verify.sh`, `storage-release-g6`, and registry recipes
  already act like package-class validation, but they encode policy in shell
  arrays and task names.

The weak signal is also clear:

- root registry recipes call `dart pub get`, but the repo currently has no
  root `pubspec.yaml`;
- workflow docs mention `.github/workflows`, while workflows are currently
  under `.github/archite_workflows`;
- many package-local `pubspec.lock` and `pubspec_overrides.yaml` files make
  local development and release state easy to confuse;
- package families repeat boilerplate in platform clients, factories, native
  loaders, generated SDK tests, README/export files, and release gates.

## Architecture Principles

1. Keep packages real until projection is proven.
2. Treat the concept graph as an overlay, not a replacement for pub.
3. Prefer generated facts over hand-authored metadata.
4. Add hand-authored metadata only where inference is weak and value is proven.
5. Generate boilerplate, not product judgment.
6. Every generated artifact must be deterministic, inspectable, and traceable.
7. Conformance checks must be read-only in CI.
8. Mutation commands must be explicit and separate from validation commands.
9. Optimize for "work by purpose" without hiding file/package reality.
10. Kill experiments quickly when graph quality or DX degrades.

## Proposed Graph Model

### Node Types

- `concept`: `platform.ads`, `platform.social`, `storage.cloudkit`,
  `inference.stt`, `logger.triage`
- `package`: `xsoulspace_platform_ads_bridge`,
  `universal_storage_cloudkit`, `xsoulspace_inference_vosk_flutter`
- `surface`: exported library, public class, capability interface, CLI,
  generator
- `implementation`: provider, adapter, raw binding, Flutter wrapper,
  no-op fallback
- `artifact`: generated file, projected package, registry archive, metadata JSON
- `gate`: test, analyzer command, generator check, registry smoke, publish dry-run
- `lifecycle`: experimental, internal, beta, stable, deprecated, blocked
- `owner`: person, area, or package family

### Edge Types

- `depends_on`: from pubspec dependencies
- `exports`: package to public library surface
- `implements`: implementation to interface or capability
- `wraps`: adapter/wrapper to raw binding or upstream SDK
- `bridges`: bridge package to two concepts
- `generated_from`: generated artifact to source spec, upstream lock, or snapshot
- `validated_by`: concept/package/artifact to gate
- `owned_by`: package/concept to owner
- `releases_with`: compatibility chain or release group
- `blocks`: failing gate to lifecycle state

### Evidence And Confidence

Every inferred node or edge should include:

```yaml
evidence:
  - path: pkgs/xsoulspace_platform_ads_bridge/pubspec.yaml
    reason: dependency on platform core and ads interface
confidence: inferred|declared|verified
```

This prevents false authority. The graph should make uncertainty visible.

## Development Steps And Options

### Step 0: Baseline Repair And Guardrails

Purpose: stop architecture work from being polluted by known operational drift.

Actions:

- decide whether `.github/archite_workflows` is archival or should move to
  `.github/workflows`;
- decide whether root tooling needs a root `pubspec.yaml` or `registry/` should
  become its own Dart package;
- document that validation commands must be read-only unless named as mutation
  commands;
- keep existing packages as source of truth.

Validation:

```bash
git status --short
just docs-check
just registry-test
```

Kill criteria:

- root tooling cannot run without hidden local state;
- validation mutates package files without an explicit mutation command.

### Step 1: Read-Only Concept Graph Index

Purpose: prove that concept-level navigation beats prefix search.

Build a read-only CLI later:

```bash
dart tool/xs_graph.dart build --output build/concept_graph/concepts.json
dart tool/xs_graph.dart query platform.ads --impact
dart tool/xs_graph.dart query inference.stt --packages --tests
dart tool/xs_graph.dart query storage.cloudkit --release-gates
```

Inputs:

- `pkgs/*/pubspec.yaml`
- exported `lib/*.dart`
- imports and package references
- `README.md` first heading and status language
- `tool/upstream_lock.json`
- `tool/api_snapshot.json`
- tests under package `test/`
- registry tooling outputs when available
- readiness artifact when available

Outputs:

- `build/concept_graph/concepts.json`
- small text report for humans
- evidence paths and confidence values

Success criteria:

- builds in under 10 seconds;
- identifies at least three non-obvious cross-family edges;
- answers impact queries better than package-prefix search;
- no hand-authored metadata required for the first version.

Kill criteria:

- more than 20 percent of useful edges need manual correction;
- graph cannot map concepts to tests/gates better than prefix search.

### Step 2: Concept Conformance Rules

Purpose: turn graph insight into lightweight safety.

Initial rules:

- interface packages must not depend on provider packages;
- foundation packages may depend on interfaces, not concrete adapters;
- generated SDK packages must have upstream lock and `--check` generator path;
- public packages must not contain local path dependencies;
- every public package must map to at least one concept and one gate;
- mutation recipes must not run inside read-only validation.

Inspired by:

- [Nx project graph](https://nx.dev/docs/features/explore-graph)
- [Nx conformance rules](https://nx.dev/docs/reference/conformance/overview)
- [Pants dependency validation](https://www.pantsbuild.org/dev/docs/using-pants/validating-dependencies)

Example commands:

```bash
dart tool/xs_graph.dart conformance --check
dart tool/xs_graph.dart conformance --fix-metadata
```

Success criteria:

- CI can run conformance in read-only mode;
- violations are specific and include evidence paths;
- fixes are explicit and reviewable.

Kill criteria:

- conformance produces noisy false positives;
- developers bypass it because errors are not actionable.

### Step 3: Minimal Declarative Metadata

Purpose: fill gaps that inference cannot reliably solve.

Only after Step 1 proves value, allow package metadata under a namespaced key:

```yaml
xsoulspace:
  concepts:
    - platform.ads
    - monetization.ads
    - sdk.crazygames
  lifecycle:
    state: public
    stability: beta
  owner: platform
  generated: false
  release_gate: platform-sdk-verify
```

Rules:

- generated facts beat declared facts;
- declared facts must be validated against code where possible;
- metadata must be small enough to maintain by hand;
- do not create central manifests until package-local metadata proves painful.

Alternative: family manifests such as `concepts/platform.yaml`.

Use family manifests only for roadmap-level state or ownership review. They are
more likely to drift because they live away from code.

### Step 4: Contract Test Kits

Purpose: reduce repeated testing while preserving behavior.

Candidate reusable suites:

- `PlatformClientContract`
- `PlatformFactoryContract`
- `NativeLoaderContract`
- `GeneratedSdkContract`
- `BrowserWrapperContract`
- `StorageProviderContract`
- `PurchaseProviderContract`
- `AdProviderContract`

The tests should stay behavioral. Avoid snapshot-only tests that merely check
that generated text contains a symbol.

Success criteria:

- migrate two packages to one shared contract helper;
- reduce repeated test code without hiding failure reasons;
- package-local tests remain easy to run.

Kill criteria:

- failures become harder to diagnose;
- contracts force fake uniformity over real platform differences.

### Step 5: Codemod-First Normalization

Purpose: identify mechanical repetition before introducing generators.

Codemod dry-run targets:

- normalize `PlatformAdapterFactory` implementations;
- extract repeated `PlatformClient` lifecycle boilerplate;
- normalize native loader candidate path logic;
- normalize generated SDK test structure;
- normalize package README/export patterns.

Example command:

```bash
dart tool/xs_recipe.dart detect platform-factory-shape --changed
dart tool/xs_recipe.dart apply platform-client-boilerplate --dry-run
```

Reference: [OpenRewrite recipes](https://docs.openrewrite.org/concepts-and-explanations/recipes).

Success criteria:

- detects real repetition with low false positives;
- proposed edits are small and readable;
- no production code is generated yet.

Kill criteria:

- codemod requires more review than hand edits;
- detection is too brittle across normal style variations.

### Step 6: Selective Generators

Purpose: generate only high-confidence boring artifacts.

Generate first:

- native loader shells from `native_loader_spec.yaml`;
- platform adapter shells with hooks for handwritten capabilities;
- JS SDK generator specs that standardize lock/snapshot/check behavior;
- README/export/package boilerplate from package metadata;
- graph-derived capability matrix docs.

Do not generate yet:

- high-level wrapper semantics;
- product fallbacks;
- gateway-mediated flows;
- capability implementations whose behavior is not stable;
- packages for concepts that no consumer uses.

Example native loader spec:

```yaml
kind: native_loader
package: xsoulspace_inference_vosk_raw
libraries:
  macos: [libvosk.dylib, vosk.dylib]
  linux: [libvosk.so]
  windows: [vosk.dll]
search_roots:
  - explicit_path
  - package_directory
  - process_directory
exception:
  type: VoskRawException
  code: library_not_found
```

Fast experiment:

- generate one candidate native loader into a temp directory;
- diff it against Vosk or Whisper;
- success means fewer than five hand edits needed to match behavior.

### Step 7: Materialized Package Projection

Purpose: make release artifacts deterministic and traceable without making
developer editing worse.

Do not start with virtual packages. Start with materialized projections:

```bash
dart tool/package_projection.dart \
  --packages xsoulspace_logger,xsoulspace_vkplay_js \
  --output build/projected_pkgs \
  --check
```

Projected package contents:

- `pubspec.yaml`
- `README.md`
- `CHANGELOG.md`
- `LICENSE`
- `lib/<package>.dart`
- optional `lib/raw.dart`
- selected `lib/src/**`
- generated `.projection.json`
- source hash
- projection version
- template version

Then run:

```bash
cd build/projected_pkgs/xsoulspace_logger
dart pub publish --dry-run --ignore-warnings
```

Later, the registry can build archives from projected packages instead of raw
`pkgs/*`.

Success criteria:

- projected package is deterministic;
- archive provenance is obvious;
- developer can understand published bytes in under 30 seconds;
- no IDE workflow depends on editing generated projection directories.

Kill criteria:

- projection diverges from source in surprising ways;
- debugging publish output becomes harder;
- developers start editing projected files.

### Step 8: Pub Workspace Pilot

Purpose: evaluate official Dart workspace behavior on a small subset only.

Reference: [Dart pub workspaces](https://dart.dev/tools/pub/workspaces).

Candidate subset:

- `xsoulspace_platform_core_interface`
- `xsoulspace_platform_foundation`
- `xsoulspace_platform_social_interface`
- `xsoulspace_platform_gamification_interface`
- `xsoulspace_platform_multiplayer_interface`

Questions:

- Does a single root lockfile reduce or increase friction?
- Do existing SDK constraints support workspace resolution?
- Do local overrides become simpler or more constrained?
- Can focused package tests still run easily?
- Does shared resolution create unrelated conflicts?

Success criteria:

- fewer lock/override changes;
- focused package checks remain fast;
- dependency resolution is easier to explain.

Kill criteria:

- unrelated packages block each other;
- too many SDK constraints need churn;
- package-local workflows become less predictable.

### Step 9: Concept-Aware Change Planning

Purpose: let developers and agents work by purpose.

Example workflow:

```bash
xs graph focus platform.ads
xs graph why-dep xsoulspace_platform_crazygames_ads xsoulspace_crazygames_js
xs change plan platform.ads --add-provider crazygames
xs validate concept platform.ads --changed
```

The planner should produce:

- impacted concepts;
- files/packages likely to change;
- public API surfaces;
- tests and gates to run;
- release and registry impact;
- generated artifacts to refresh.

This starts as planning only. Automated edits come later through explicit
codemod or generator commands.

### Step 10: Virtual Packages And Dynamic Regrouping

Purpose: explore the long-term idea without betting the repo on it early.

Virtual packages may be useful for:

- generated aggregate packages;
- compatibility exports;
- temporary migration packages;
- registry-only meta-packages;
- documentation bundles.

Rules:

- every virtual package must materialize before use;
- generated package archives must include projection provenance;
- no runtime or analyzer workflow should depend on invisible packages;
- virtual packages cannot be the first implementation of a concept.

This is a research track, not the initial plan.

## Development Roadmap

### Phase 1: Observe

Build the read-only concept graph from existing facts. No source behavior
changes.

Deliverables:

- `tool/xs_graph.dart build`
- `tool/xs_graph.dart query`
- `build/concept_graph/concepts.json`
- evidence-based report

### Phase 2: Govern

Add conformance rules and small metadata only where inference fails.

Deliverables:

- `tool/xs_graph.dart conformance --check`
- package-local `xsoulspace:` metadata for a small subset
- CI-safe read-only report

### Phase 3: Normalize

Use codemods and shared contract tests to reduce duplicated shape.

Deliverables:

- one codemod dry-run
- one shared contract test helper
- two migrated packages

### Phase 4: Generate

Generate proven mechanical shells only.

Deliverables:

- one native loader generator experiment
- one adapter-shell or docs-generation experiment
- one shared generator contract test

### Phase 5: Project

Materialize release packages from source packages and metadata.

Deliverables:

- `tool/package_projection.dart`
- two projected packages
- publish dry-run from projection
- registry archive comparison

### Phase 6: Recompose

Evaluate workspace mode, aggregate packages, and dynamic grouping once graph
quality is proven.

Deliverables:

- small pub workspace pilot
- one generated aggregate package
- decision record on virtual packages

## Fast Experiments

### Experiment A: Concept Graph Report

Scope: read-only.

Command:

```bash
dart tool/xs_graph.dart build --report
```

Success:

- under 10 seconds;
- answers three concept queries;
- exposes at least three cross-family edges.

### Experiment B: Platform Client Boilerplate Detector

Scope: detection only.

Command:

```bash
dart tool/xs_recipe.dart detect platform-client-boilerplate
```

Success:

- detects repeated registry/events/require/maybe boilerplate;
- no false positives outside platform packages.

### Experiment C: Generated SDK Contract Test

Scope: test helper only.

Targets:

- `xsoulspace_crazygames_js`
- `xsoulspace_vkplay_js`

Success:

- test LOC drops;
- stale generated file and stale lock failures stay clear.

### Experiment D: Native Loader Spec

Scope: temp output only.

Target:

- Vosk or Whisper raw loader.

Success:

- generated candidate differs by fewer than five semantic edits.

### Experiment E: Materialized Projection

Scope: two packages.

Targets:

- `xsoulspace_logger`
- `xsoulspace_vkplay_js`

Success:

- deterministic projected dirs;
- publish dry-run works from projected package;
- projection provenance is obvious.

## External Precedents

Use these as reference points, not systems to copy wholesale:

- [Dart pub workspaces](https://dart.dev/tools/pub/workspaces): official
  workspace behavior and constraints.
- [Nx project graph](https://nx.dev/docs/features/explore-graph): graph-based
  project and task navigation.
- [Nx conformance](https://nx.dev/docs/reference/conformance/overview):
  workspace-wide rules and ownership checks.
- [Bazel aspects](https://bazel.build/versions/8.0.0/extending/aspects?hl=en):
  walking a dependency graph to derive secondary artifacts.
- [Pants dependency validation](https://www.pantsbuild.org/dev/docs/using-pants/validating-dependencies):
  dependency rules as data.
- [Backstage Software Catalog](https://backstage.io/docs/features/software-catalog/):
  ownership and lifecycle metadata across software systems.
- [OpenRewrite recipes](https://docs.openrewrite.org/concepts-and-explanations/recipes):
  codemods and refactoring as repeatable recipes.
- [Code Property Graph specification](https://cpg.joern.io/): queryable graph
  representation of source code.

## Key Risks

- The graph can become stale if hand-authored metadata is introduced too early.
- Generated code can freeze today's bad abstractions.
- Projection can make publish output harder to debug if provenance is weak.
- Pub workspace migration can introduce shared-resolution conflicts.
- Conformance can become noise if rules are not evidence-based.
- A "concept platform" can become a heavier framework than the package sprawl.

## Recommendation

Start with the read-only graph. It is the smallest bet that tests the core idea:
can we work by concept better than by package prefix?

If yes, add conformance. If conformance catches real architectural drift, add
minimal metadata. If metadata and graph queries remain useful, generate boring
shells and contract tests. Only after that should package projection and virtual
package experiments begin.

The target is not fewer packages at any cost. The target is less accidental
architecture: fewer hand-maintained surfaces, clearer impact, smaller repeated
code, faster validation, and code navigation by purpose.
