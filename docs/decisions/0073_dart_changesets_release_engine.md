# ADR 0073: dart_changesets — pub.dev-primary release engine

- Status: Accepted. Engine landed in [pkgs/dart_changesets](../../pkgs/dart_changesets)
  and on 2026-11-20 (same day) EXTRACTED to the standalone
  [Arenukvern/dart_changesets](https://github.com/Arenukvern/dart_changesets)
  repository — composite action + reusable publish workflow; this repo
  consumes it via thin workflows. Bootstrap (first manual
  publishes + per-package automated-publishing toggles) is owner-paced.
- Date: 2026-11-20
- North Star impact: `clarifies` — publishing was the repo's weakest
  automated surface (registry unsupported, pub.dev drift already real:
  monetization_foundation 0.9.0 on pub.dev vs 0.10.0 in-tree). No contract
  package changes; the release center moves.
- Supersedes: the registry v1 publish flow ([PUBLISHING.md](../../PUBLISHING.md)
  pre-2026-11-20); `registry_publish.yml` keeps workflow_dispatch only.

## Context

Four in-house repos each solved release automation separately, all on
release-please (Node) plus hand-maintained scripts:

- **mcp_flutter**: single-train (`.` + `VERSION` + `extra-files`),
  `sync_version.sh` with hard-coded file lists, bash publish train, per-package
  OIDC mint (ADR 0021 there: setup-dart JWTs expire in minutes — the last
  train package failed with `Invalid JWT token`).
- **oka**: same single-train shape, pubspec list hand-maintained.
- **intentcall**: `linked-versions` train + a **Dart CLI**
  (`tool/intentcall/bin/intentcall.dart`) whose `publishRelease` is
  production-proven: static checks → skip-existing → dependency wait → strict
  dry-run → `--force` → wait-visible. It also measured the decisive pub.dev
  constraint (2026-11-08): automated publishing is **ref-gated per package
  tag** — a consolidated train run can publish only the one package its
  triggering ref names; per-tag fan-out with dependency waits is the mandated
  architecture.
- **skill_steward** (Node): the contract-over-scripts pattern — declared
  gates and config, not free-floating shell.

Ecosystem alternatives fell short: **melos** is conventional-commit-driven
and imperative (no PR-bot flow); **firehose** publishes but versions nothing;
**Changie** is changelog-only; **release-please** has no Dart workspace
plugin — dependents' constraints never cascade, and every repo re-derives
its config by hand (the lists rot). The changesets *model* (intent files in
PRs → assembled version PR → graph-aware cascade → per-package cadence)
exists nowhere in the Dart ecosystem, and it removes the conventional-commits
dependency entirely (this repo's history is `wip:`-heavy by choice).

## Decision

Build **`dart_changesets`** as a pure-Dart package in `pkgs/` — named
generically so it can be extracted into a standalone repository, zero
imports from repo-internal tooling, dependencies only from pub.dev
(`args`, `path`, `pub_semver`, `yaml`). It releases itself through its own
flow.

- **Intent files** (`.changesets/*.md`, changesets frontmatter format) carry
  release intent; max bump wins per package; unknown package names are fatal.
- **Graph-aware cascade**: dependents whose caret constraints no longer admit
  the new version get a patch bump (configurable) plus constraint rewrite;
  private (`publish_to: none`) dependents get constraint-only rewrites.
  Versions and constraints computed with `package:pub_semver` (caret on 0.x
  semantics included) — no regex version math. Trains topologically sort
  dependencies before dependents.
- **One version PR** per train ("chore: version packages"), assembled on
  main pushes; merging it pushes one `<package>-v<version>` tag per release
  and dispatches one publish run per tag. No PAT required: GITHUB_TOKEN push
  events do not trigger workflows, so publishes are dispatched explicitly via
  `gh workflow run`.
- **Publish leg** is a port of intentcall's `publishRelease` (attribution in
  source): static checks → skip-existing → typed BOOTSTRAP gate for
  never-published packages → dependency wait → strict dry-run → `--force` →
  wait-visible. OIDC rides `dart-lang/setup-dart`; short-lived-JWT risk is
  gone because each run publishes exactly one package.
- **Doctor gates**: no path deps in publishable packages (pub refuses them —
  measured on Dart 3.14); no publishable→private dependencies (the
  dependency-driven conversion rule: the engine lane publishes only when a
  publishable package needs it); changelog/README/LICENSE presence; SDK-floor
  drift warning; pub.dev presence census.
- **Rate-limit reality**: new-package creation caps at ~12/day — bootstrap of
  ~67 never-published packages is owner-paced across days (or a
  dart-lang/pub-dev limit raise); version uploads self-heal via re-dispatch.

The engine lane's 13 `publish_to: none` packages stay out of trains until
conversion; the gate makes the conversion mandatory exactly when a dependency
requires it.

## Consequences

- Registry tooling (`registry/`) stays for inspection; `registry_publish.yml`
  is dispatch-only. Consumers pinned to `pub.xsoulspace.dev` must migrate to
  plain pub.dev constraints.
- Sibling repos (mcp_flutter, oka, intentcall) keep their working trains;
  consolidating them onto `dart_changesets` is a separate future decision —
  the extraction seam is already clean.
- The changesets intent format keeps release intent reviewable per PR and
  works regardless of commit-message style; the cost is that a forgotten
  intent file simply doesn't release — `just changesets-status` and the
  assembler are the standing reminders.
- Attribution: design inspired by
  [changesets](https://github.com/changesets/changesets) and
  [@changesets/action](https://github.com/changesets/action); documented in
  the package README.

## Non-claims

- No package was published while landing this ADR; bootstrap is owner action.
- The OIDC end-to-end publish leg is proven in intentcall and ported, but its
  first live run in THIS repository happens after merge (first tag push) —
  that run is the remaining verification debt.
- pub.dev's exact version-upload rate limit is undocumented ("much higher"
  per maintainers); the train design tolerates any value via skip-existing.

## Postscript (2026-11-21): sibling repos migrated

The "separate later decision" above was made: `intentcall`, `oka`,
`mcp_flutter`, and `ecsly` now run this engine for their pub package trains
(assembly + per-tag publish via `Arenukvern/dart_changesets@v1`; release-please
trains retired). Per-repo decisions: intentcall `ecec7a5` (PUBLISHING.md),
oka ADR 0054 (`0086269`), mcp_flutter `1990ddfc` (binary harness + MCP
Registry dispatch kept separate), ecsly `1e713d6` (`release-validation.yml`
kept). Engine gained workspace-glob package discovery (`a18b895`, 44/44) and
a configurable Flutter version in the reusable publish workflow (`265bf3e`).
All four repos' first live assemble runs succeeded on GitHub runners
(2026-11-20T23:02–23:07Z). pub.dev bootstrap (first-publish + per-package
automated-publishing toggles) remains owner-paced per repo.
