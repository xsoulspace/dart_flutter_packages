library;

export 'src/native_bridge/native_client.dart';

// TASK B (ADR 0015): last_answer embeds the harness as its first domain
// host — the daemon backend is part of this package's public surface so
// hosts own the lifecycle in-process (AcpStdioServer over an in-memory
// channel); the core still learns no ACP and no Dart.
export 'src/harness_acp_backend.dart';
