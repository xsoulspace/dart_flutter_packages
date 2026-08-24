# universal_storage_mesh

Serverless peer-to-peer storage provider
([ADR 0010](../../docs/decisions/0010_mesh_sync_architecture.md)). Every
device is a full replica with equal standing; QR pairing establishes trust;
sync is opportunistic over whatever link exists, or manual. Convergence is
decided by [universal_storage_convergence](../universal_storage_convergence)
identically at every replica.

North Star: [docs/north_star.mdx](docs/north_star.mdx).

## Quick start

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

final provider = MeshStorageProvider();
await provider.initWithConfig(
  MeshStorageConfig(storePath: appDocsDir, peerId: myDeviceId),
);

// Attach one or more transports (LAN, BLE, ... or the fake in tests).
provider.attachTransport(myTransport);

// Register peers you have paired with (QR scan outcome).
await provider.registerPeer(peerRecordFromQr);

// Local-first CRUD — never touches the network.
await provider.createFile('notes/todo.json', '{"done":false}');
print(await provider.getFile('notes/todo.json'));

// Opportunistic sync: unreachable peers are skipped silently.
await provider.sync();
```

## Behavior contract

- **Local-first**: reads/writes resolve instantly from the local replica.
- **Opportunistic**: `sync()` exchanges version vectors + deltas/snapshots
  with every reachable paired peer; failures mean "try later".
- **Deterministic**: concurrent writes converge to the same winner on all
  replicas (HLC-LWW; kernel-owned semantics).
- **Durable**: state survives restarts; compaction via `compactAll()` keeps
  logs bounded while lagging peers catch up via snapshots.

## Packages

| Package                            | Responsibility                                  |
| ---------------------------------- | ----------------------------------------------- |
| `universal_storage_mesh`           | Provider, pairing records, sync sessions        |
| `universal_storage_mesh_transport` | `MeshTransport` seam + fake transport + framing |
| `universal_storage_convergence`    | The kernel (merge, ordering, compaction)        |

Status: alpha (`0.1.0-dev`). QR pairing crypto and a real LAN transport are
the next milestones.
