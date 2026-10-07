/// Composable permission contract shared across products.
///
/// One vocabulary, three decisions, composition by policy chain:
///
/// - [PermissionKind] — the closed action-kind vocabulary (ACP today;
///   OS consent joins as new names in later minor versions).
/// - [PermissionRequest] — pure request data every transport adapts to
///   at its edge.
/// - [PermissionDecision] — allow / deny / **escalate**; escalate is
///   "this decider holds no authority", the verb that lets a policy
///   chain hand a request UP instead of guessing.
/// - [PermissionStance] — the three coarse positions mainstream agents
///   expose (ask / workspaceEdits / fullAccess) as policy factories.
/// - [PermissionPolicy] + `policies` — total, pure deciders and their
///   composition (allow-lists, grants, first-match).
/// - [PermissionGate] — the runner; a chain that ends escalated with
///   no sink DENIES (deny-by-default is structural).
/// - [PermissionGrantStore] — where allowances live, with the
///   single-use law for `once` grants.
///
/// Transports (ACP round-trips, CRDT doc routers, OS dialogs) stay
/// product-side: they adapt wire shapes to [PermissionRequest], route
/// [PermissionEscalate] through their own consent flow, and persist
/// grants. Nothing here performs I/O.
library;

export 'src/permission_decision.dart';
export 'src/permission_gate.dart';
export 'src/permission_grants.dart';
export 'src/permission_kind.dart';
export 'src/permission_policy.dart';
export 'src/permission_request.dart';
export 'src/permission_stance.dart';
export 'src/policies.dart';
