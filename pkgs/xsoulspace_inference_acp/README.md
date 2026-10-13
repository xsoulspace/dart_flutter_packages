# ACP inference adapter

The adapter reuses the ACP transport and host-owned services. `conversationKey`
is an explicit owner-supplied identity: when present, turns retain a session per
working directory and reconnect uses `session/load`. Unsupported resume refuses;
it never silently creates a replacement conversation or replays a mutation.
Omit it for isolated one-shot sessions.

`clientServices` binds authorized filesystem/terminal handlers. Capabilities are
derived from actual handlers; service calls require live session authorization.
Callbacks must propose candidate changes through their native owner, not write
authoritative files. The adapter supplies no filesystem writer or OS sandbox.

A nonempty inference `toolRegistry` requires `boundMcpServers` to reference an
already installed authorized host MCP surface. Otherwise it returns
`acp_tool_registry_unbound` before connecting. No tool catalog is copied and
filesystem services alone do not bind arbitrary world tools.

`cancelActive` forwards ACP cancellation and discards late inference completion;
stream sessions forward cancellation too. A cancelled turn remains occupied
until its underlying request settles. Provider availability is not a live coding
or external-agent compatibility claim.

For owner-durable conversations, inject `sessionPersistence` and an explicit
`providerIdentity`. The read/save callbacks contain only the remote session cursor;
`authorize(binding, previous)` must prove current native participant, workspace
and provider/MCP grants before every resumed or cached prompt. Binding mismatch,
revocation, failed persistence and unsupported `session/load` refuse rather than
forking or replaying. Descriptor fingerprints and saved IDs are never grants.

Plain and streaming prompts project only the current request. Nonempty explicit
`messages` take precedence; otherwise `SituationMessagesCodec` renders the supplied
system prompt, projected fragments (including source/absence/tool notes) and
current decision prompt. Each declared role/content pair is serialized into an
existing ACP text block. ACP has no native system/assistant/tool role channel in
`session/prompt`: this is informational role text, with semantic role flattening,
not provider-native role privilege. No transcript is stored/appended and no hidden
world state is read. Agent-retained remote history is separate from this codec.
