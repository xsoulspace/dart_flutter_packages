import 'package:test/test.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

void main() {
  group('PermissionGrant.covers', () {
    test('matches kind and exact subject, never prefixes', () {
      const grant = PermissionGrant(
        kind: PermissionKind.edit,
        subject: 'lib/foo.dart',
      );
      final edit = PermissionRequest(
        id: 'r1',
        title: 't',
        kind: PermissionKind.edit,
        subject: 'lib/foo.dart',
      );
      final sibling = PermissionRequest(
        id: 'r2',
        title: 't',
        kind: PermissionKind.edit,
        subject: 'lib/bar.dart',
      );
      final unsubjected = PermissionRequest(
        id: 'r3',
        title: 't',
        kind: PermissionKind.edit,
      );
      expect(grant.covers(edit), isTrue);
      expect(grant.covers(sibling), isFalse);
      // A subject-scoped grant does not cover a subjectless request.
      expect(grant.covers(unsubjected), isFalse);
    });

    test('expiry bounds the match', () {
      final grant = PermissionGrant(
        kind: PermissionKind.read,
        expiresAt: DateTime.utc(2026, 10, 8),
      );
      final request = PermissionRequest(
        id: 'r1',
        title: 't',
        kind: PermissionKind.read,
      );
      expect(grant.covers(request, now: DateTime.utc(2026, 10, 7)), isTrue);
      expect(grant.covers(request, now: DateTime.utc(2026, 10, 9)), isFalse);
    });
  });

  group('InMemoryPermissionGrantStore', () {
    test('a once grant is consumed by the answer that uses it', () {
      final store = InMemoryPermissionGrantStore();
      store.record(
        const PermissionGrant(
          kind: PermissionKind.execute,
          scope: PermissionGrantScope.once,
        ),
      );
      final request = PermissionRequest(
        id: 'r1',
        title: 't',
        kind: PermissionKind.execute,
      );
      expect(store.consumeMatching(request), isNotNull);
      expect(store.consumeMatching(request), isNull);
    });

    test('session grants answer repeatedly', () {
      final store = InMemoryPermissionGrantStore();
      store.record(
        const PermissionGrant(
          kind: PermissionKind.edit,
          scope: PermissionGrantScope.session,
        ),
      );
      final request = PermissionRequest(
        id: 'r1',
        title: 't',
        kind: PermissionKind.edit,
      );
      expect(store.consumeMatching(request), isNotNull);
      expect(store.consumeMatching(request), isNotNull);
    });

    test('recording replaces the live grant for the same slot', () {
      final store = InMemoryPermissionGrantStore();
      store.record(
        const PermissionGrant(kind: PermissionKind.edit, subject: 'lib/a.dart'),
      );
      store.record(
        const PermissionGrant(kind: PermissionKind.edit, subject: 'lib/a.dart'),
      );
      expect(
        store.consumeMatching(
          PermissionRequest(
            id: 'r1',
            title: 't',
            kind: PermissionKind.edit,
            subject: 'lib/a.dart',
          ),
        ),
        isNotNull,
      );
      store.revoke(kind: PermissionKind.edit, subject: 'lib/a.dart');
      expect(
        store.consumeMatching(
          PermissionRequest(
            id: 'r2',
            title: 't',
            kind: PermissionKind.edit,
            subject: 'lib/a.dart',
          ),
        ),
        isNull,
      );
    });

    test('revoke filters by kind and subject', () {
      final store = InMemoryPermissionGrantStore()
        ..record(const PermissionGrant(kind: PermissionKind.read))
        ..record(const PermissionGrant(kind: PermissionKind.edit));
      store.revoke(kind: PermissionKind.read);
      expect(
        store.consumeMatching(
          PermissionRequest(id: 'r1', title: 't', kind: PermissionKind.read),
        ),
        isNull,
      );
      expect(
        store.consumeMatching(
          PermissionRequest(id: 'r2', title: 't', kind: PermissionKind.edit),
        ),
        isNotNull,
      );
    });
  });

  group('GrantPolicy', () {
    test('a matching grant allows at the granted scope', () {
      final store = InMemoryPermissionGrantStore()
        ..record(
          const PermissionGrant(
            kind: PermissionKind.move,
            scope: PermissionGrantScope.session,
          ),
        );
      final decision = GrantPolicy(store).decide(
        PermissionRequest(id: 'r1', title: 't', kind: PermissionKind.move),
      );
      expect(
        decision,
        equals(const PermissionAllow(PermissionGrantScope.session)),
      );
    });

    test('a miss escalates — a grant store never invents a deny', () {
      final store = InMemoryPermissionGrantStore();
      final decision = GrantPolicy(store).decide(
        PermissionRequest(id: 'r1', title: 't', kind: PermissionKind.delete),
      );
      expect(decision, isA<PermissionEscalate>());
    });
  });
}
