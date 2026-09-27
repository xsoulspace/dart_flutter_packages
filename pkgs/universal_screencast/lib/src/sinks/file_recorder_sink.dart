import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../frame.dart';
import '../frame_sink.dart';

/// Durable frame recording with a receipt manifest per frame.
///
/// Two artifacts land in [directory]: `<base>.mjpeg` — the raw frame
/// payloads concatenated (playable by any MJPEG tool when frames are
/// JPEG) — and `<base>.meta.jsonl`, one JSON receipt per frame with its
/// byte offset, aligning with the plagiarism project's ADR-035 contract
/// families (`recording`, `receipts`). Frames are evidence-grade bytes
/// here; the sink never invents content (`video != evidence`, but a
/// receipt makes it checkable).
class FileRecorderSink implements FrameSink {
  /// Creates a recorder writing `<directory>/<base>.mjpeg` and
  /// `<directory>/<base>.meta.jsonl`.
  FileRecorderSink({required this._directory, this._base = 'frames'});

  final String _directory;
  final String _base;
  RandomAccessFile? _framesFile;
  RandomAccessFile? _metaFile;
  int _offset = 0;
  bool _closed = false;

  @override
  String get id => 'recorder';

  @override
  List<String> get acceptedContentTypes => const ['*'];

  /// Path of the frame payload file.
  String get framesPath => '$_directory/$_base.mjpeg';

  /// Path of the receipt manifest.
  String get metaPath => '$_directory/$_base.meta.jsonl';

  @override
  Future<void> push(Frame frame) async {
    if (_closed) throw SinkClosedException(id);
    _framesFile ??= await File(
      framesPath,
    ).create(recursive: true).then((file) => file.open(mode: FileMode.append));
    _metaFile ??= await File(
      metaPath,
    ).create(recursive: true).then((file) => file.open(mode: FileMode.append));
    await _framesFile!.writeFrom(frame.bytes);
    final receipt = jsonEncode({
      'sourceId': frame.sourceId,
      'sequence': frame.sequence,
      'revision': frame.revision,
      'offset': _offset,
      'byteLength': frame.bytes.length,
      'contentType': frame.contentType,
      'capturedAt': frame.capturedAt.toIso8601String(),
    });
    await _metaFile!.writeFrom(utf8.encode('$receipt\n'));
    _offset += frame.bytes.length;
  }

  @override
  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    await _framesFile?.flush();
    await _framesFile?.close();
    await _metaFile?.flush();
    await _metaFile?.close();
    _framesFile = null;
    _metaFile = null;
  }
}
