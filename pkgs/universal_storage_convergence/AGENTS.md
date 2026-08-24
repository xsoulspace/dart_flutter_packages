# universal_storage_convergence — Working Agreement

## Scope (sub-star boundary, ADR 0011)

- This package is the convergence kernel serving two parents: Universal
  Storage mesh sync and ecsly world sync. Neither may override kernel
  semantics (ordering, version vectors, fold rules).
- No knowledge of storage namespaces, worlds, actors, or transports. Ever.
- New merge strategies require property tests proving commutative,
  idempotent folds before shipping.

## Obligations

- HLC monotonicity must survive process restarts
  (`hlcRestoreMonotonic`); never trust a regressing wall clock.
- Compaction retires the op log; after compaction, lagging peers are served
  snapshots (`needsSnapshotFor`), never deltas.
- Kernel changes need conformance evidence from all consuming parents.

## Validation

```bash
just check universal_storage_convergence
```
