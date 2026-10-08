# ADR Index

Harness product decisions (0002–0005, 0007, 0009, 0012–0028, 0030,
0033–0035) moved to `~/xs/ecsai_harness/docs/decisions/` with
[0036](0036_harness_product_relocated.md).

| ADR | Status | Title |
| --- | --- | --- |
| [0001](0001_native_ffi_bridge_acp.md) | Accepted | Native FFI bridge for Apple Foundation |
| [0006](0006_universal_storage_production_hardening.md) | Accepted | Universal Storage hardening |
| [0008](0008_env_config_store.md) | Accepted | EnvConfig store |
| [0010](0010_mesh_sync_architecture.md) | Accepted | Mesh sync architecture |
| [0011](0011_convergence_kernel_dual_mode.md) | Accepted | Convergence kernel, dual mode |
| [0029](0029_convergence_kernel_presence_and_sequence_strategy.md) | Accepted | Convergence kernel presence and sequence |
| [0031](0031_presence_link_topology_and_session_foundation.md) | Accepted | Presence link topology |
| [0032](0032_convergence_kernel_composite_strategy.md) | Accepted | Convergence kernel composite strategy |
| [0036](0036_harness_product_relocated.md) | Accepted | Harness product relocated to ecsai_harness |
| [0037](0037_universal_automation_family.md) | Accepted | `universal_automation_*` family: drivers, screencast, WebRTC |
| [0038](0038_automation_kernel_unification.md) | Accepted | The family is the automation kernel; toolkit/IntentCall adoption |
| [0039](0039_mesh_session_aead_channel_crypto.md) | Accepted | Mesh session AEAD channel crypto (`universal_storage_session_aead`) |
| [0040](0040_universal_driver_macos.md) | Accepted | `universal_driver_macos`: AXUIElement observation + CGEvent synthesis driver |
| [0041](0041_mesh_realtime_durable_push_channel.md) | Accepted | Mesh realtime durable push channel (live mode + change notifications) |
| [0042](0042_content_addressed_chunk_store.md) | Accepted | Content-addressed chunk store — native binary deltas (amends 0010 §5) |
| [0043](0043_storage_shrink_exploration_tracks.md) | Accepted | Storage-shrink and tooling exploration tracks (triggers + kill criteria) |
| [0044](0044_behavior_dynamics_contract.md) | Accepted | Behavior dynamics contract — declarative input profiles for humans and agents (amends 0037/0038) |
| [0045](0045_flutter_web_driving_primitives.md) | Accepted | Flutter-web driving primitives — live-DOM name location, focus restoration, JIT/AOT tier matrix |
| [0046](0046_universal_automation_toolkit.md) | Accepted | `universal_automation_toolkit` — the family's agent surface: declarative plans, CLI, MCP |
| [0047](0047_world_layer_zone_journeys.md) | Accepted | The world layer — app- and game-agnostic zone journeys (`universal_storage_world`; MeshWorldSession; member-codec seam; host-driven pulse) |
| [0048](0048_interest_managed_exchange.md) | Accepted | Interest-managed mesh exchange — the additive `sub` frame, priority, budget; absent sub = wildcard (amends 0010 §4) |
| [0049](0049_binary_member_lane.md) | Accepted | Binary members — the manifest/lane split: `MeshBlobLane`, dialer-symmetric push/absorb chunks, claimed blob plane (implements 0042) |
| [0050](0050_realtime_plane.md) | Accepted | The realtime event plane out of the box: `universal_storage_realtime` — envelope, link (heartbeats/droppable/reliable), host + arbiter seam (vosges = reference shape) |
| [0051](0051_mlx_c_rust_engine_and_model_mesh.md) | Accepted | mlx-c native inference engine (Rust host) behind the `laya_native` symbols + the model mesh ladder (phones join first, hosting capability-gated; routing = world concern) |
| [0052](0052_semantic_view_grammar.md) | Accepted | `universal_automation_semantics` — the semantic view grammar: declarative views, ref-stable observations, diffs |
| [0053](0053_coordinate_pointer_verbs.md) | Accepted | Coordinate pointer verbs — `clickAt`/`moveTo`/`drag`, capability-gated, MoE-lowered from day one |
