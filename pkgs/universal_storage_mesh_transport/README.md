# universal_storage_mesh_transport

Transport seam for mesh sync
([ADR 0010](../../docs/decisions/0010_mesh_sync_architecture.md)): peer and
session interfaces, length-prefixed framing for stream transports, and a
deterministic fake transport for headless tests. Real radio transports
(LAN mDNS+TCP first, BLE-class later) are separate packages implementing
`MeshTransport`.
