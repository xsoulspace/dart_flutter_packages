import 'dart:io';
import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  test('direct provider race: two createFile on same path', () async {
    final dir = await Directory.systemTemp.createTemp('race2_');
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: dir.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(dir),
        ),
      ),
    );
    Object? e1;
    Object? e2;
    final f1 = provider.createFile('x.txt', 'from-1');
    final f2 = provider.createFile('x.txt', 'from-2');
    try { await f1; } catch (e) { e1 = e; }
    try { await f2; } catch (e) { e2 = e; }
    // ignore: avoid_print
    print('E1=${e1?.runtimeType} E2=${e2?.runtimeType}');
    await dir.delete(recursive: true);
  });

  test('saveFile race through StorageService', () async {
    final dir = await Directory.systemTemp.createTemp('race3_');
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: dir.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(dir),
        ),
      ),
    );
    final service = StorageService(provider);
    Object? e1;
    Object? e2;
    final f1 = service.saveFile('y.txt', 'from-1');
    final f2 = service.saveFile('y.txt', 'from-2');
    try { await f1; } catch (e) { e1 = e; }
    try { await f2; } catch (e) { e2 = e; }
    // ignore: avoid_print
    print('S1=${e1?.runtimeType} S2=${e2?.runtimeType}');
    expect(e1, isNull, reason: 'first saveFile should not throw');
    expect(e2, isNull, reason: 'second saveFile should not throw (race guard)');
    await dir.delete(recursive: true);
  });
}
