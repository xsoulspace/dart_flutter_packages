@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  test('same owner nested claims retain outer lease', () {
    final locks = FileLockTable();
    final owner = Object();
    final other = Object();
    expect(locks.claim('a', owner), isTrue);
    expect(locks.claim('a', owner), isTrue);
    locks.release('a', other);
    locks.release('a', owner);
    expect(locks.ownerOf('a'), same(owner));
    expect(locks.claim('a', other), isFalse);
    locks.release('a', owner);
    expect(locks.claim('a', other), isTrue);
  });

  test('resolves missing descendants and rejects symlink escapes', () {
    final base = Directory.systemTemp.createTempSync('path-policy-');
    addTearDown(() => base.deleteSync(recursive: true));
    final inside = Directory('${base.path}/inside')..createSync();
    final outside = Directory('${base.path}/outside')..createSync();
    final policy = WorkspacePathPolicy(inside.path);
    Link('${inside.path}/escape').createSync(outside.path);
    Link('${inside.path}/dangling').createSync('${outside.path}/absent');
    expect(policy.resolve('new/file'), '${policy.rootPath}/new/file');
    expect(() => policy.resolve('escape/new/file'), throwsArgumentError);
    expect(() => policy.resolve('dangling/new'), throwsArgumentError);
    expect(policy.allows('../outside'), isFalse);
    expect(policy.resolve('"./new/../file"'), '${policy.rootPath}/file');
  });

  test(
    'policy changes after construction are checked for lexical and real paths',
    () {
      final base = Directory.systemTemp.createTempSync('late-policy-');
      addTearDown(() => base.deleteSync(recursive: true));
      final actual = File('${base.path}/actual')..writeAsStringSync('kept');
      Link('${base.path}/alias').createSync(actual.path);
      var denied = <String>{};
      final seen = <String>[];
      final policy = WorkspacePathPolicy(
        base.path,
        pathAllowed: (path) {
          seen.add(path);
          return !denied.contains(path);
        },
      );
      final root = policy.rootPath;
      expect(policy.resolve('alias'), '$root/actual');
      expect(seen, containsAll(['$root/alias', '$root/actual']));
      denied = {'$root/actual'};
      expect(policy.allows('alias'), isFalse);
      denied = {'$root/alias'};
      expect(policy.allows('alias'), isFalse);
      denied = {};
      expect(policy.resolve('alias'), '$root/actual');
      final next = Directory('$root/next')..createSync();
      policy.rootPath = next.path;
      expect(policy.resolve('file'), '${next.path}/file');
    },
  );
}
