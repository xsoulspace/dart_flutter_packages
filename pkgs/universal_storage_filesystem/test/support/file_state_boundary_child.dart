import 'dart:convert';
import 'dart:io';

import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

Future<void> main(List<String> args) async {
  final workspace = Directory(args[0]);
  final marker = File(args[1]);
  final mode = int.parse(args[2]);
  final boundary = FileSystemWriteBoundary.values.byName(args[3]);
  final provider = FileSystemStorageProvider(
    onWriteBoundary: (observed) {
      if (observed != boundary) return;
      final target = File('${workspace.path}/owned');
      final stages = Directory('${workspace.path}/.us/tmp')
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (file) => {
              'path': file.path,
              'content': file.readAsStringSync(),
              'mode': file.statSync().mode & 0xfff,
            },
          )
          .toList();
      marker.writeAsStringSync(
        jsonEncode({
          'pid': pid,
          'boundary': observed.name,
          'executable': Platform.resolvedExecutable,
          'target_content': target.readAsStringSync(),
          'target_mode': target.statSync().mode & 0xfff,
          'stages': stages,
          'journals': Directory('${workspace.path}/.us/journal')
              .listSync()
              .whereType<File>()
              .map((file) => file.readAsStringSync())
              .toList(),
        }),
        flush: true,
      );
      stdin.readLineSync();
      // Parent must kill this exact owned process; resumption is not a proof.
      throw StateError('Boundary pause unexpectedly resumed');
    },
  );
  await provider.initWithConfig(
    FileSystemConfig(
      filePathConfig: FilePathConfig.create(
        path: workspace.path,
        macOSBookmarkData: MacOSBookmark.fromDirectory(workspace),
      ),
    ),
  );
  await provider.restoreFileState(
    'owned',
    StorageFileState(content: 'candidate private bytes', mode: mode),
  );
  throw StateError('Boundary was not observed');
}
