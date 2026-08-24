# universal_storage_convergence

Convergence kernel shared by Universal Storage mesh sync and ecsly world
sync ([ADR 0011](../../docs/decisions/0011_convergence_kernel_dual_mode.md)).

Dual mode: every replica keeps an incrementally-folded state plus a pending
op log. Ships hybrid logical clocks, version vectors, op records, and
pluggable merge strategies (`LwwMapStrategy` first). Knows nothing about
storage namespaces, worlds, actors, or transports.
