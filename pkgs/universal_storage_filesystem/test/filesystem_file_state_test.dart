import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/src/posix_file_state_native.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void foreignMode(String path, int mode) {
  final libc = DynamicLibrary.process();
  final allocate = libc
      .lookupFunction<
        Pointer<Void> Function(UintPtr),
        Pointer<Void> Function(int)
      >('malloc');
  final release = libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final chmod = libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, int)
      >('chmod');
  final bytes = [...utf8.encode(path), 0];
  final pointer = allocate(bytes.length).cast<Uint8>();
  try {
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    expect(chmod(pointer, mode), 0);
  } finally {
    release(pointer.cast<Void>());
  }
}

void main() {
  late Directory root;
  late FileSystemStorageProvider provider;
  Future<FileSystemStorageProvider> open() async {
    final result = FileSystemStorageProvider();
    await result.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: root.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(root),
        ),
      ),
    );
    return result;
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('file_state_');
    provider = await open();
  });
  tearDown(() async {
    await provider.dispose();
    root.deleteSync(recursive: true);
  });

  Map<String, Object> prepared(int mode) => {
    'schema_version': 2,
    'namespace': '_root',
    'operation_id': 'prepared',
    'sequence': 999,
    'operation_type': 'update',
    'stage': 'prepared',
    'relative_path': 'owned',
    'temp_relative_path': '.us/tmp/_root/prepared.tmp',
    'checksum': normalizedSha256Hex('candidate'),
    'file_mode': mode,
    'file_state_profile': storagePosixRwxProfile,
  };

  group('POSIX state', () {
    test('embedded NUL refuses without truncating native path', () {
      final path = '${root.path}/prefix';
      expect(() => PosixStage('$path\u0000suffix'), throwsArgumentError);
      expect(File(path).existsSync(), false);
      PosixStage('$path\\u0000suffix').close();
      expect(File('$path\\u0000suffix').existsSync(), true);
    });
    test(
      'owner-unreadable intended state refuses before publication',
      () async {
        await provider.createFile('owned', 'private');
        final before = File('${root.path}/owned').readAsBytesSync();
        for (final mode in [0, 0x80, 0x3f]) {
          await expectLater(
            provider.restoreFileState(
              'owned',
              StorageFileState(content: 'bad', mode: mode),
            ),
            throwsA(isA<UnsupportedOperationException>()),
          );
        }
        expect(File('${root.path}/owned').readAsBytesSync(), before);
        expect(File('${root.path}/owned').statSync().mode & 0xfff, 0x1a4);
      },
    );
    test(
      'exclusive descriptor is0600 before and while private bytes are written',
      () {
        final file = File('${root.path}/stage');
        final stage = PosixStage(file.path);
        try {
          expect(file.statSync().mode & 0xfff, 0x180);
          stage
            ..writeContent('private bytes')
            ..flush();
          expect(file.readAsStringSync(), 'private bytes');
          expect(file.statSync().mode & 0xfff, 0x180);
          expect(
            () => PosixStage(file.path),
            throwsA(isA<FileSystemException>()),
          );
          expect(file.readAsStringSync(), 'private bytes');
        } finally {
          stage.close();
        }
      },
    );
    test(
      'new files are0644 and profile declares actual POSIX authority',
      () async {
        expect(provider.fileStateProfile, storagePosixRwxProfile);
        await provider.createFile('new', 'value');
        final state = await provider.readFileState('new');
        expect(state.content, 'value');
        expect(state.mode, 0x1a4);
        final entries = File(
          '${root.path}/.us/journal/_root.log',
        ).readAsLinesSync().map((line) => jsonDecode(line) as Map).toList();
        expect(entries.first['schema_version'], 2);
        expect(entries.first['file_mode'], 0x1a4);
        expect(entries.first['file_state_profile'], storagePosixRwxProfile);
      },
    );
    for (final mode in [0x180, 0x1a4, 0x1ed]) {
      test('update/delete/restore preserves actual mode$mode', () async {
        const content = 'private original';
        final original = StorageFileState(content: content, mode: mode);
        await provider.restoreFileState('owned', original);
        await provider.updateFile('owned', 'changed');
        expect((await provider.readFileState('owned')).mode, mode);
        await provider.deleteFile('owned');
        expect((await provider.readFileState('owned')).mode, isNull);
        await provider.restoreFileState('owned', original);
        final restored = await provider.readFileState('owned');
        expect(restored.content, content);
        expect(restored.mode, mode);
        await provider.restoreFileState(
          'owned',
          const StorageFileState(content: null, mode: null),
        );
        expect(File('${root.path}/owned').existsSync(), false);
      });
    }
    test('existing special mode refuses observation and write', () async {
      await provider.createFile('owned', 'private');
      foreignMode('${root.path}/owned', 0x980);
      expect(File('${root.path}/owned').statSync().mode & 0xfff, 0x980);
      await expectLater(provider.readFileState('owned'), throwsFormatException);
      await expectLater(
        provider.updateFile('owned', 'bad'),
        throwsFormatException,
      );
      expect(File('${root.path}/owned').readAsStringSync(), 'private');
      foreignMode('${root.path}/owned', 0x180);
    });
    test(
      'symlink/nonregular/special requested mode refuse without effects',
      () async {
        await provider.createFile('real', 'unchanged');
        Link('${root.path}/link').createSync('real');
        Directory('${root.path}/dir').createSync();
        for (final name in ['link', 'dir']) {
          await expectLater(
            provider.readFileState(name),
            throwsA(isA<UnsupportedOperationException>()),
          );
          await expectLater(
            provider.restoreFileState(
              name,
              const StorageFileState(content: 'bad', mode: 0x180),
            ),
            throwsA(isA<UnsupportedOperationException>()),
          );
        }
        await expectLater(
          provider.restoreFileState(
            'real',
            const StorageFileState(content: 'bad', mode: 0x980),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(await provider.getFile('real'), 'unchanged');
      },
    );
    test(
      'exclusive staging failure cannot publish or checkpoint new content',
      () {
        PosixStage('${root.path}/exclusive').close();
        expect(
          () => writePosixStage('${root.path}/exclusive', 'bad', 0x180),
          throwsA(isA<FileSystemException>()),
        );
        expect(File('${root.path}/exclusive').readAsStringSync(), '');
        expect(File('${root.path}/.us/journal/_root.log').existsSync(), false);
      },
    );
    for (final alreadyPublished in [false, true]) {
      test(
        'preparedmode mismatch refuses '
        '${alreadyPublished ? 'published target' : 'stage'} without chmod',
        () async {
          await provider.createFile('owned', 'baseline');
          final target = File('${root.path}/owned');
          final temp = File('${root.path}/.us/tmp/_root/prepared.tmp');
          temp.parent.createSync(recursive: true);
          writePosixStage(
            alreadyPublished ? '${target.path}.replacement' : temp.path,
            'candidate',
            0x1a4,
          );
          if (alreadyPublished) {
            File('${target.path}.replacement').renameSync(target.path);
          }
          final journal = File('${root.path}/.us/journal/_root.log')
            ..writeAsStringSync('${jsonEncode(prepared(0x180))}\n');
          final before = target.readAsStringSync();
          final beforeMode = target.statSync().mode & 0xfff;
          final reopened = await open();
          expect(target.readAsStringSync(), before);
          expect(target.statSync().mode & 0xfff, beforeMode);
          expect(
            (reopened.lastRecoveryReport['totals']
                as Map)['replayed_operations'],
            0,
          );
          expect(journal.lengthSync(), greaterThan(0));
          await reopened.dispose();
        },
      );
    }
    for (final invalid in <Map<String, Object>>[
      {'file_mode': 0x980},
      {'file_mode': '0600'},
      {'file_state_profile': 'unknown'},
      {'operation_type': 'unknown'},
      {'stage': 'unknown'},
      {'checksum': ''},
    ]) {
      test('malformed file-state journal refuses $invalid', () async {
        await provider.createFile('owned', 'baseline');
        final target = File('${root.path}/owned');
        final journal = File('${root.path}/.us/journal/_root.log');
        final row = prepared(0x180)..addAll(invalid);
        journal.writeAsStringSync('${jsonEncode(row)}\n');
        final reopened = await open();
        expect(target.readAsStringSync(), 'baseline');
        expect(target.statSync().mode & 0xfff, 0x1a4);
        expect(
          (reopened.lastRecoveryReport['totals']
              as Map)['corrupted_journal_entries'],
          1,
        );
        expect(
          (reopened.lastRecoveryReport['totals'] as Map)['replayed_operations'],
          0,
        );
        expect(journal.lengthSync(), greaterThan(0));
        await reopened.dispose();
      });
    }
    test('invalid native mode leaves only restrictive stage, '
        'no published checkpoint', () {
      final stage = File('${root.path}/failed-stage');
      expect(
        () => writePosixStage(stage.path, 'private', 0x980),
        throwsArgumentError,
      );
      expect(stage.statSync().mode & 0xfff, 0x180);
      expect(File('${root.path}/.us/journal/_root.log').existsSync(), false);
      expect(File('${root.path}/owned').existsSync(), false);
    });
    test('corrupt staged content refuses before atomic replacement', () async {
      await provider.createFile('owned', 'baseline');
      final temp = File('${root.path}/.us/tmp/_root/prepared.tmp');
      temp.parent.createSync(recursive: true);
      writePosixStage(temp.path, 'corrupt', 0x180);
      File(
        '${root.path}/.us/journal/_root.log',
      ).writeAsStringSync('${jsonEncode(prepared(0x180))}\n');
      final reopened = await open();
      expect(await reopened.getFile('owned'), 'baseline');
      expect(temp.readAsStringSync(), 'corrupt');
      expect(
        (reopened.lastRecoveryReport['totals'] as Map)['replayed_operations'],
        0,
      );
      await reopened.dispose();
    });
    test(
      'valid prepared mode/content publishes atomically and verifies on reopen',
      () async {
        final target = File('${root.path}/owned');
        writePosixStage(target.path, 'baseline', 0x180);
        final temp = File('${root.path}/.us/tmp/_root/prepared.tmp');
        temp.parent.createSync(recursive: true);
        writePosixStage(temp.path, 'candidate', 0x1ed);
        File(
          '${root.path}/.us/journal/_root.log',
        ).writeAsStringSync('${jsonEncode(prepared(0x1ed))}\n');
        final reopened = await open();
        expect(target.readAsStringSync(), 'candidate');
        expect(target.statSync().mode & 0xfff, 0x1ed);
        expect(temp.existsSync(), false);
        expect(
          (reopened.lastRecoveryReport['totals'] as Map)['replayed_operations'],
          1,
        );
        await reopened.dispose();
      },
    );
  }, skip: !supportsPosixFileState);
}
