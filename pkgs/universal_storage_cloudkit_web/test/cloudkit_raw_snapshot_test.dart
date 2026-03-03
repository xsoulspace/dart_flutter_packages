import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('generated CloudKit raw bindings snapshot is present', () {
    final root = Directory.current.path;
    final dtsFile = File(
      path.join(root, 'tool', 'generated', 'cloudkit.generated.d.ts'),
    );
    final snapshotFile = File(path.join(root, 'tool', 'api_snapshot.json'));
    final rawBindingFile = File(
      path.join(root, 'lib', 'src', 'raw', 'cloudkit_raw.g.dart'),
    );

    expect(dtsFile.existsSync(), isTrue);
    expect(snapshotFile.existsSync(), isTrue);
    expect(rawBindingFile.existsSync(), isTrue);

    final dts = dtsFile.readAsStringSync();
    final snapshot = snapshotFile.readAsStringSync();
    final rawBinding = rawBindingFile.readAsStringSync();

    expect(dts, contains('CloudKit'));
    expect(snapshot, contains('"symbol": "CloudKit"'));
    expect(snapshot, contains('"generated": "lib/src/raw/cloudkit_raw.g.dart"'));
    expect(rawBinding, contains('external JSAny? get cloudKitGlobal;'));
    expect(rawBinding, contains('bool get hasCloudKitGlobal'));
  });
}
