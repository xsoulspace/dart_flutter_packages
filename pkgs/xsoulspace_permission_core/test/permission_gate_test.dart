import 'package:test/test.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

PermissionRequest readRequest() => PermissionRequest(
  id: 'r1',
  title: 'Read the tree',
  kind: PermissionKind.read,
);

void main() {
  test('the first final decision in the chain wins', () async {
    final gate = PermissionGate(
      policies: [
        const KindAllowlistPolicy(allowed: {PermissionKind.read}),
        const AllowAllPolicy(),
      ],
      onEscalate: (request) => throw StateError('never reached'),
    );
    expect(await gate.resolve(readRequest()), isA<PermissionAllow>());
  });

  test('a fully-escalated request reaches the sink', () async {
    final gate = PermissionGate(
      policies: [PermissionStance.ask.policy()],
      onEscalate: (request) async => const PermissionDeny('user said no'),
    );
    final decision = await gate.resolve(readRequest());
    expect(decision, equals(const PermissionDeny('user said no')));
  });

  test('no sink means an unresolved request DENIES — structurally', () async {
    final gate = PermissionGate(policies: [PermissionStance.ask.policy()]);
    final decision = await gate.resolve(readRequest());
    expect(decision, isA<PermissionDeny>());
  });

  test('the sink answer is used verbatim, allow included', () async {
    var seen = '';
    final gate = PermissionGate(
      policies: const [],
      onEscalate: (request) {
        seen = request.id;
        return Future.value(const PermissionAllow(PermissionGrantScope.always));
      },
    );
    final decision = await gate.resolve(readRequest());
    expect(seen, 'r1');
    expect(
      decision,
      equals(const PermissionAllow(PermissionGrantScope.always)),
    );
  });

  test('decisions distinguish final from escalations', () {
    expect(const PermissionAllow().isFinal, isTrue);
    expect(const PermissionDeny().isFinal, isTrue);
    expect(const PermissionEscalate().isFinal, isFalse);
  });
}
