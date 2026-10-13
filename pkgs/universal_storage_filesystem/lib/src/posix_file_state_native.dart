import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

bool get supportsPosixFileState => Platform.isMacOS || Platform.isLinux;

final _libc = DynamicLibrary.process();
final _malloc = _libc
    .lookupFunction<
      Pointer<Void> Function(UintPtr),
      Pointer<Void> Function(int)
    >('malloc');
final _free = _libc
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'free',
    );
final _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Int32, VarArgs<(Uint32,)>),
      int Function(Pointer<Uint8>, int, int)
    >('open');
final _write = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');
final _fchmod = _libc
    .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
      'fchmod',
    );
final _fsync = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'fsync',
);
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);

/// An exclusive 0600 descriptor; private bytes never precede its permissions.
final class PosixStage {
  PosixStage(String path) {
    if (path.contains('\u0000')) throw ArgumentError.value(path, 'path');
    if (!supportsPosixFileState) {
      throw UnsupportedError('POSIX file state unavailable');
    }
    final bytes = [...utf8.encode(path), 0];
    final pointer = _malloc(bytes.length).cast<Uint8>();
    if (pointer == nullptr) throw StateError('POSIX allocation failed');
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final flags = Platform.isMacOS
          ? 1 | 0x200 | 0x800 | 0x100
          : 1 | 0x40 | 0x80 | 0x20000;
      _descriptor = _open(pointer, flags, 0x180);
      if (_descriptor < 0) {
        throw FileSystemException('Exclusive POSIX staging open failed', path);
      }
      // fchmod removes umask dependence before any content is written.
      setMode(0x180);
    } catch (_) {
      close();
      rethrow;
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  int _descriptor = -1;

  void writeContent(String content) {
    final bytes = utf8.encode(content);
    if (bytes.isEmpty) return;
    final pointer = _malloc(bytes.length).cast<Uint8>();
    if (pointer == nullptr) throw StateError('POSIX allocation failed');
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final count = _write(
          _descriptor,
          pointer + offset,
          bytes.length - offset,
        );
        if (count <= 0) {
          throw const FileSystemException('POSIX staging write failed');
        }
        offset += count;
      }
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  void setMode(int mode) {
    if (mode < 0 || mode > 0x1ff) throw ArgumentError.value(mode, 'mode');
    if (_fchmod(_descriptor, mode) != 0) {
      throw const FileSystemException('POSIX staging fchmod failed');
    }
  }

  void flush() {
    if (_fsync(_descriptor) != 0) {
      throw const FileSystemException('POSIX staging fsync failed');
    }
  }

  void close() {
    if (_descriptor < 0) return;
    final descriptor = _descriptor;
    _descriptor = -1;
    if (_close(descriptor) != 0) {
      throw const FileSystemException('POSIX staging close failed');
    }
  }
}

void writePosixStage(
  String path,
  String content,
  int mode, {
  void Function()? onPrivateBytes,
}) {
  final stage = PosixStage(path);
  try {
    stage
      ..writeContent(content)
      ..flush();
    onPrivateBytes?.call();
    stage
      ..setMode(mode)
      ..flush();
  } finally {
    stage.close();
  }
}
