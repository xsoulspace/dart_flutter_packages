/// Agent-facing surface for the universal automation family: declarative
/// plans with a fail-closed runner, an observe/act/verify CLI, and an MCP
/// stdio server (ADR 0046).
///
/// The Dart composition grammar lives in the `compose` library — start
/// there:
///
/// ```dart
/// import 'package:universal_automation_toolkit/compose.dart';
/// ```
library;

export 'src/cli/toolkit_cli.dart';
export 'src/mcp/mcp_server.dart';
export 'src/plan/checks.dart';
export 'src/plan/intents.dart';
export 'src/plan/plan.dart';
export 'src/plan/steps.dart';
export 'src/runner/registry.dart';
export 'src/runner/runner.dart';
