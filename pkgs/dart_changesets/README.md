# dart_changesets

A changesets-style release engine for Dart monorepos: **intent files →
graph-aware version PRs → per-package pub.dev publish trains**.

Write a small markdown file inside a pull request declaring what changed and
how it should be released. When the PR lands, the assembler consumes all
pending intent files, computes version bumps for the declared packages plus
their transitive dependents (from the pubspec dependency graph), and opens a
single "chore: version packages" pull request. Merging it pushes one
`<package>-v<version>` tag per released package, and each tag triggers its own
publish run on pub.dev.

No conventional-commit discipline is required — release intent lives in
reviewed files, not commit messages.

## Attribution

This package is inspired by [changesets](https://github.com/changesets/changesets)
and its GitHub Action [@changesets/action](https://github.com/changesets/action)
(the original TypeScript implementation for npm monorepos). The intent-file
format, the "Version Packages" pull-request flow, and the dependent-cascade
model follow that design. Differences are ecosystem-driven:

- Versions and constraints are computed with `package:pub_semver` against
  `pubspec.yaml` files (caret semantics on `0.x` included), not
  `package.json` semver ranges.
- The dependency graph comes from pub workspaces / pubspec files, not npm
  workspaces.
- Publishing targets pub.dev and follows its constraints: automated
  publishing is ref-gated per package tag, so one tag pushes one publish run
  (ordering emerges from dependency waits plus skip-existing self-healing),
  and the first publish of a brand-new package must be done manually by an
  uploader before the per-package "Automated publishing" toggle can be
  enabled.

## CLI

```bash
dart run dart_changesets add          # write a new intent file (interactive)
dart run dart_changesets status       # pending changesets → affected packages → proposed versions
dart run dart_changesets version --check   # exit 1 when a version PR is due (CI assembly)
dart run dart_changesets version      # apply: bump pubspecs, changelogs, consume intent files
dart run dart_changesets doctor       # release gates + pub.dev presence census
dart run dart_changesets tags         # print the release tags for the pending train (JSON)
dart run dart_changesets publish-tag --tag xsoulspace_lints-v0.1.2 [--execute] [--skip-existing]
```

## Intent file format

`.changesets/<name>.md`:

```markdown
---
'xsoulspace_monetization_interface': minor
---

Add slot-based PurchaseGate and headless list views.
```

Frontmatter maps package names to bump types (`major` | `minor` | `patch`);
the body is the changelog prose. One file may declare several packages.

## Configuration

`changesets.yaml` at the repository root (all keys optional):

```yaml
packages_dir: pkgs          # directory scanned for packages (default: pkgs)
dependent_bump: patch       # version bump applied to dependents whose constraint changed
ignore:                     # extra packages never released by this tool
  - some_internal_pkg
tag_format: '{package}-v{version}'
```

Packages marked `publish_to: none` are treated as private automatically and
excluded from releases; the doctor gate fails when a publishable package
depends on one of them (the dependency-driven conversion rule).
