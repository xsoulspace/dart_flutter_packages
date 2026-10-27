import 'permission_kind.dart';

/// OS consent kinds the Universal Automation computer-use lane needs
/// (tree + input injection, then pixels). Policies and MCP surfaces
/// should treat these as a pair — not a second consent product.
const List<PermissionKind> automationComputerUseOsKinds = [
  PermissionKind.accessibility,
  PermissionKind.screenRecording,
];
