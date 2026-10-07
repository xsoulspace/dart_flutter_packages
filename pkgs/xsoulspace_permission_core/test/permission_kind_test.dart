import 'package:test/test.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

void main() {
  test('wireName round-trips through tryParse for every kind', () {
    for (final kind in PermissionKind.values) {
      expect(PermissionKind.tryParse(kind.wireName), kind);
    }
  });

  test('tryParse is honest about unknown and absent names', () {
    expect(PermissionKind.tryParse('camera'), isNull);
    expect(PermissionKind.tryParse(null), isNull);
    expect(PermissionKind.tryParse(''), isNull);
  });

  test('coerce lands unknown and absent names on other', () {
    expect(PermissionKind.coerce('camera'), PermissionKind.other);
    expect(PermissionKind.coerce(null), PermissionKind.other);
    expect(PermissionKind.coerce('read'), PermissionKind.read);
  });

  test('a coerced request preserves its raw wire token', () {
    final request = PermissionRequest(
      id: 'r1',
      title: 'Camera access',
      kind: PermissionKind.coerce('camera'),
      wireKindOverride: 'camera',
    );
    expect(request.kind, PermissionKind.other);
    expect(request.wireKind, 'camera');
  });

  test('requests compare by value', () {
    final a = PermissionRequest(
      id: 'r1',
      title: 't',
      kind: PermissionKind.read,
    );
    final b = PermissionRequest(
      id: 'r1',
      title: 't',
      kind: PermissionKind.read,
    );
    final c = PermissionRequest(
      id: 'r2',
      title: 't',
      kind: PermissionKind.read,
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
