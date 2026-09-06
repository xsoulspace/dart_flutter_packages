# universal_storage_convergence

Convergence kernel shared by Universal Storage mesh sync and ecsly world sync
([ADR 0011](../../docs/decisions/0011_convergence_kernel_dual_mode.md)).

Pure Dart. Zero dependencies beyond `meta`. Knows nothing about storage,
worlds, or transports — messages in, messages out.

North Star: [docs/north_star.mdx](docs/north_star.mdx).

## Core types

| Type                               | Role                                                         |
| ---------------------------------- | ------------------------------------------------------------ |
| `Hlc`                              | Hybrid logical clock; total order `(wall, counter, actorId)` |
| `VersionVector`                    | Per-actor high-water marks; dedupe + anti-entropy header     |
| `OpRecord`                         | One immutable convergence event (`ttl` marks it ephemeral)   |
| `Snapshot`                         | Folded state at a version-vector watermark                   |
| `ConvergenceDoc`                   | Dual-mode replica: folded state + pending op log             |
| `MergeStrategy` / `LwwMapStrategy` | Pluggable fold semantics (v1: LWW map)                       |
| `RgaTextStrategy`                  | Sequence merge for block text (ADR 0029; streamed agent text) |
| ephemeral ops                      | TTL'd presence registry; never durable, never snapshotted     |

Ephemeral contract (ADR 0029 §1): `applyLocalEphemeral` issues a TTL'd op
that rides the normal convergence path but folds into `ephemeralState`
only — never into durable state, snapshots, or the version vector.
`sweepEphemeral(now)` drops expired ops (commutative, idempotent);
`applyRemote(ops, now:)` drops already-expired deliveries.

## Quick start

```dart
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

final local = ConvergenceDoc(docId: 'settings', actorId: 'device-a');
final remote = ConvergenceDoc(docId: 'settings', actorId: 'device-b');

// Local write: folds immediately, returns the op for durable append.
final op = local.applyLocal({'k': 'theme', 'v': 'dark'}, DateTime.now());

// Remote delivery: idempotent, order-independent.
remote.applyRemote([op]);
print(remote.state); // {theme: dark}
```

## Guarantees

- Any replica order of the same op set yields identical state (property-tested).
- Re-applying ops is a no-op (version-vector dedupe).
- HLC monotonicity survives process restarts (`hlcRestoreMonotonic`).
- After `compact()`, lagging peers catch up via snapshots (`needsSnapshotFor`).
