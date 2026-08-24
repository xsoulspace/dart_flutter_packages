# universal_storage_mesh

Serverless peer-to-peer storage provider
([ADR 0010](../../docs/decisions/0010_mesh_sync_architecture.md)). Every
device is a full replica with equal standing; QR pairing establishes trust;
sync is opportunistic over whatever link exists, or manual. Convergence is
decided by [universal_storage_convergence](../universal_storage_convergence)
identically at every replica.
