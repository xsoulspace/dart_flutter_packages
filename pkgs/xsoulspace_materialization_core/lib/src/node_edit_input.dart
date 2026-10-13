import 'node_payload.dart';

/// Resolved edit data supplied to a native materializer binding.
///
/// This is neither permission nor an executable request. The native adapter
/// attaches its root, policy, locks and verification before performing an edit.
class NodeEditInput {
  const NodeEditInput({
    required this.path,
    required this.action,
    required this.anchor,
    this.body,
    this.payload,
    this.previewOnly = false,
  });

  /// Workspace-relative destination resolved by the caller's native adapter.
  final String path;

  /// An action declared by the selected binding.
  final String action;

  /// Anchor in that binding's declared currency.
  final String anchor;

  /// Legacy transport fragment; admission converts it to declared payload data.
  final String? body;
  final NodeEditPayload? payload;

  /// Planning request; native implementations must return proposed bytes only.
  final bool previewOnly;
}
