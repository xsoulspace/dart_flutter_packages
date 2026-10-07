import 'permission_decision.dart';
import 'permission_kind.dart';
import 'permission_policy.dart';
import 'policies.dart';

/// The coarse consent stance for a context — the same three positions
/// the mainstream coding agents expose (codex Read Only/Auto/Full
/// Access, zed's per-mode switcher, cursor ask/auto/YOLO), mapped onto
/// the shared kind vocabulary.
///
/// The stance is a POLICY FACTORY, not an enforcer: a transport binds
/// [policy]'s output wherever its consent flow needs it. `ask` is the
/// default everywhere and means escalate-everything — deny-by-default
/// is shown, never assumed.
enum PermissionStance {
  /// Every request escalates to the consent surface (the default).
  ask,

  /// Reads, edits, and moves inside the working set are auto-allowed;
  /// anything with reach beyond it (execute, delete, other) still
  /// escalates: a command execution is not a workspace edit.
  workspaceEdits,

  /// Everything auto-allowed. An explicit per-context user decision,
  /// never a default.
  fullAccess;

  /// The kinds [workspaceEdits] auto-allows — the working set.
  static const Set<PermissionKind> workspaceKinds = {
    PermissionKind.read,
    PermissionKind.edit,
    PermissionKind.move,
  };

  /// This stance as a total policy.
  PermissionPolicy policy() => switch (this) {
    ask => const KindAllowlistPolicy(
      allowed: {},
      otherwise: PermissionEscalate(to: 'user'),
    ),
    workspaceEdits => const KindAllowlistPolicy(
      allowed: workspaceKinds,
      otherwise: PermissionEscalate(to: 'user'),
    ),
    fullAccess => const AllowAllPolicy(PermissionGrantScope.session),
  };

  /// Parses a persisted stance name; unknown/absent → [ask] (the
  /// conservative reading of a value nobody vouches for).
  static PermissionStance fromName(final String? name) =>
      PermissionStance.values.firstWhere(
        (stance) => stance.name == name,
        orElse: () => PermissionStance.ask,
      );
}
