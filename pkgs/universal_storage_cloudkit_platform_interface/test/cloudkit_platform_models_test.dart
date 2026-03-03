import 'package:test/test.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

void main() {
  test('CloudKitRecord map roundtrip keeps values', () {
    final record = CloudKitRecord(
      recordName: 'abc',
      path: 'foo/bar.txt',
      content: 'hello',
      checksum: 'sum',
      size: 5,
      updatedAt: DateTime.utc(2026, 3, 3, 10, 0, 0),
      changeTag: 'ctag',
    );

    final roundtrip = CloudKitRecord.fromMap(record.toMap());
    expect(roundtrip.recordName, equals(record.recordName));
    expect(roundtrip.path, equals(record.path));
    expect(roundtrip.content, equals(record.content));
    expect(roundtrip.checksum, equals(record.checksum));
    expect(roundtrip.size, equals(record.size));
    expect(roundtrip.updatedAt, equals(record.updatedAt));
    expect(roundtrip.changeTag, equals(record.changeTag));
  });
}
