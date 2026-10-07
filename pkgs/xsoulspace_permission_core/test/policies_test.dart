import 'package:test/test.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

PermissionRequest requestOf(
  final PermissionKind kind, {
  final String wireKind = 'read',
  final String? subject,
}) => PermissionRequest(
  id: 'r-${kind.wireName}',
  title: 't',
  kind: kind,
  wireKindOverride: wireKind,
  subject: subject,
);

void main() {
  group('PermissionStance.policy', () {
    test('ask escalates everything, reads included', () {
      final policy = PermissionStance.ask.policy();
      expect(
        policy.decide(requestOf(PermissionKind.read)),
        isA<PermissionEscalate>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.execute)),
        isA<PermissionEscalate>(),
      );
    });

    test('workspaceEdits auto-allows the working set only', () {
      final policy = PermissionStance.workspaceEdits.policy();
      expect(
        policy.decide(requestOf(PermissionKind.read)),
        isA<PermissionAllow>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.edit)),
        isA<PermissionAllow>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.move)),
        isA<PermissionAllow>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.execute)),
        isA<PermissionEscalate>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.delete)),
        isA<PermissionEscalate>(),
      );
      expect(
        policy.decide(requestOf(PermissionKind.other)),
        isA<PermissionEscalate>(),
      );
    });

    test('fullAccess allows at session scope', () {
      final decision = PermissionStance.fullAccess.policy().decide(
        requestOf(PermissionKind.execute),
      );
      expect(
        decision,
        equals(const PermissionAllow(PermissionGrantScope.session)),
      );
    });

    test('fromName falls back to ask for unknown names', () {
      expect(
        PermissionStance.fromName('workspaceEdits'),
        PermissionStance.workspaceEdits,
      );
      expect(PermissionStance.fromName('YOLO'), PermissionStance.ask);
      expect(PermissionStance.fromName(null), PermissionStance.ask);
    });
  });

  test('KindAllowlistPolicy escalates unlisted kinds', () {
    const policy = KindAllowlistPolicy(allowed: {PermissionKind.read});
    expect(
      policy.decide(requestOf(PermissionKind.read)),
      isA<PermissionAllow>(),
    );
    expect(
      policy.decide(requestOf(PermissionKind.other)),
      isA<PermissionEscalate>(),
    );
  });

  test('FirstMatchPolicy takes the first final decision', () {
    final chain = FirstMatchPolicy([
      const KindAllowlistPolicy(allowed: {PermissionKind.read}),
      const AllowAllPolicy(),
    ]);
    expect(
      chain.decide(requestOf(PermissionKind.read)),
      isA<PermissionAllow>(),
    );
    expect(
      // The allow-all rung answers what the allow-list escalated.
      chain.decide(requestOf(PermissionKind.execute)),
      isA<PermissionAllow>(),
    );
  });

  test('FirstMatchPolicy composes all-escalate into one escalate', () {
    final chain = FirstMatchPolicy([
      PermissionStance.ask.policy(),
      const KindAllowlistPolicy(allowed: {}),
    ]);
    final decision = chain.decide(requestOf(PermissionKind.read));
    expect(decision, isA<PermissionEscalate>());
  });
}
