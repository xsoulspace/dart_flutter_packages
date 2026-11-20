# Publishing Guide

Packages in this repository publish to **pub.dev** through the
`dart_changesets` release engine (ADR 0073). The legacy
GitHub-backed registry flow (`pub.xsoulspace.dev`) is **PAUSED —
unsupported**; its tooling stays in `registry/` for revival, but nothing
publishes to it automatically anymore.

Design inspiration and attribution: [changesets](https://github.com/changesets/changesets)
and [@changesets/action](https://github.com/changesets/action) (the
TypeScript original for npm). The engine itself lives in
[pkgs/dart_changesets](pkgs/dart_changesets) and releases itself through the
flow below.

## Flow

```
PR with an intent file (.changesets/*.md)
  → merge to main
  → assembler opens "chore: version packages" PR
     (version bumps + dependent-constraint cascades + changelogs, computed
      from the pubspec graph)
  → merge that PR
  → one <package>-v<version> tag per released package
  → one publish run per tag (dependency waits + skip-existing self-heal)
```

No conventional-commit discipline is required — release intent lives in
reviewed files, not commit messages.

## Authoring an intent

Inside any pull request:

```bash
just changesets-add        # interactive
# or write .changesets/<name>.md by hand:
#   ---
#   'xsoulspace_monetization_interface': minor
#   ---
#   Changelog prose.
```

Frontmatter maps package names to `major` | `minor` | `patch`; the body is
changelog prose. Dependents whose caret constraints no longer admit the new
version are bumped (patch by default, configurable via `dependent_bump` in
[changesets.yaml](changesets.yaml)) and get their constraint rewritten in the
same train — dependencies always publish before dependents.

## Release gates

Run before relying on a train (also wired into `just release-gate`):

```bash
just release-gate          # doctor: path-dep gate, private-dep gate, docs, census
just changesets-status     # pending intents → planned releases
just publish-preflight <package>   # full publish dry-run, no upload
```

Gate rules:

- Publishable packages must not declare `path:` dependencies (pub refuses
  them at publish time — measured on Dart 3.14).
- Publishable packages must not depend on `publish_to: none` packages. The
  engine lane (inference mlx/laya/openai/openrouter/…, materialization,
  meaning, local_serve) stays private until a publishable package needs it;
  conversion = remove `publish_to: none` and rewrite its path dependencies
  to hosted constraints in dependency order.
- Each release needs a matching `CHANGELOG.md` entry (the assembler writes
  it).

## Bootstrap (first publish of a new package)

pub.dev cannot automate a package's first release:

1. `cd pkgs/<package> && dart pub publish` (or `flutter pub publish`) —
   sign in with the uploader account in the browser.
2. On pub.dev open the package → **Admin → Automated publishing** → enable
   for repository `xsoulspace/dart_flutter_packages`, environment `pub.dev`,
   tag pattern `<package>-v{{version}}`.
3. Re-run the publish (skip-existing keeps it idempotent).

Never-published packages are listed by `just release-gate` (census section).
Rate limit: pub.dev caps **new-package creation at ~12/day** (4 in a burst)
— spread first publishes across days or file an issue on
`dart-lang/pub-dev` for a raise. Version uploads of existing packages have
much higher limits; trains self-heal via per-tag re-dispatch.

## CI

| Workflow | Trigger | Job |
|---|---|---|
| `dart_changesets_assemble.yml` | push to main | applies the pending train onto `changesets/version-packages` and opens/updates the version PR |
| `dart_changesets_publish.yml` | version-PR merge | pushes one tag per release and dispatches one publish run per tag |
| `dart_changesets_publish.yml` | tag push / dispatch | publishes exactly the tagged package (OIDC via `dart-lang/setup-dart`; `id-token: write`; environment `pub.dev`) |

No stored secrets are required. `workflow_dispatch` on the publish workflow
is the rescue path after a partial train: run it per straggler tag with
`execute=true`.

## Legacy registry (PAUSED)

The v1 registry flow (GitHub Releases + `registry-index` branch + gateway at
`pub.xsoulspace.dev`) is unsupported. `registry_publish.yml` lost its push
trigger; `just registry-*` recipes remain for index inspection only.
Consumers pinned to `pub.xsoulspace.dev` hosted URLs keep resolving whatever
the last published index served — migrate them to plain pub.dev constraints.
