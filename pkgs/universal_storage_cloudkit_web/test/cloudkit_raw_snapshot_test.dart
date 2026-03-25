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
    final diffFile = File(path.join(root, 'tool', 'api_diff.json'));
    final rawBindingFile = File(
      path.join(root, 'lib', 'src', 'raw', 'cloudkit_raw.g.dart'),
    );

    expect(dtsFile.existsSync(), isTrue);
    expect(snapshotFile.existsSync(), isTrue);
    expect(diffFile.existsSync(), isTrue);
    expect(rawBindingFile.existsSync(), isTrue);

    final dts = dtsFile.readAsStringSync();
    final snapshot = snapshotFile.readAsStringSync();
    final diff = diffFile.readAsStringSync();
    final rawBinding = rawBindingFile.readAsStringSync();

    expect(dts, contains('CloudKit'));
    expect(
      snapshot,
      contains('"source": "tool/generated/cloudkit.generated.d.ts"'),
    );
    expect(
      snapshot,
      contains('"generated": "lib/src/raw/cloudkit_raw.g.dart"'),
    );
    expect(snapshot, contains('"symbolCount"'));
    expect(snapshot, contains('"CloudKitGlobal"'));
    expect(snapshot, contains('"CloudKit"'));
    expect(diff, contains('"toSourceHash"'));
    expect(
      rawBinding,
      contains('external CloudKitGlobalRaw? get cloudKitGlobal;'),
    );
    expect(rawBinding, contains('bool get hasCloudKitGlobal'));
    expect(
      rawBinding,
      contains('extension type CloudKitGlobalRaw(JSObject _)'),
    );
  });
}
