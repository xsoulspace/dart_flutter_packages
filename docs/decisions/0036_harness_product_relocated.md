# ADR 0036: The harness product moved to `ecsai_harness`

- Status: Accepted
- Date: 2026-09-22
- North Star impact: `amends`
- Builds on: ADR 0012 and ADR 0025, whose texts now live in
  `~/xs/ecsai_harness/docs/decisions/`

## Context

`dart_flutter_packages` hosts many products. The agentic harness had
become the root agent surface of this repo, including uncommitted edits
that routed every task through the harness plan. Inference packages and
the shared contract packages are not that product.

## Decision

The harness product lives in `~/xs/ecsai_harness`. This monorepo no
longer contains `xsoulspace_agentic_harness`, `xsoulspace_agentic_host`,
`xsoulspace_agentic_workspace`, or
`xsoulspace_agentic_harness_flutter_profiler`.

`xsoulspace_inference_apple_foundation` keeps the FFI transport. The AFM
composition root is `xsoulspace_agentic_afm` in the product repo. Provider
packages do not depend on the harness.

Harness ADRs 0002–0005, 0007, 0009, 0012–0028, 0030, and 0033–0035 moved
with the product. Storage, mesh, and convergence ADRs stay here.

## Consequences

- Root `AGENTS.md` is a package-monorepo entrypoint again.
- Path dependency direction is one-way: `ecsai_harness` depends on
  packages in this repo. This repo does not depend on `ecsai_harness`.

## Non-claims

- This note is not the product contract. The living decision is
  `~/xs/ecsai_harness/docs/decisions/0036_harness_product_repo.md`.
- Git history of the moved files remains in this repository until the
  removal is committed.
