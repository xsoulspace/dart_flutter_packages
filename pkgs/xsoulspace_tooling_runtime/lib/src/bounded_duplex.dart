part of 'bounded_process.dart';

/// Finite resource limits for an owner-admitted newline-framed service.
final class BoundedDuplexLimits {
  const BoundedDuplexLimits({
    this.maxFrameBytes = 64 * 1024,
    this.maxOutputBytes = 8 * 1024 * 1024,
    this.maxInputBytes = 8 * 1024 * 1024,
    this.maxWrites = 1024,
    this.maxQueuedFrames = 32,
  });
  final int maxFrameBytes;
  final int maxOutputBytes;
  final int maxInputBytes;
  final int maxWrites;
  final int maxQueuedFrames;
  bool get valid => maxFrameBytes > 0 && maxOutputBytes > 0 &&
      maxInputBytes > 0 && maxWrites > 0 && maxQueuedFrames > 0;
}

/// IO projection of the existing native process owner; grants no authority.
/// Frames include their newline. Limits apply even before listening or while
/// paused. Refusal enters the same owner termination/settlement ladder.
final class BoundedDuplexHandle {
  BoundedDuplexHandle._(this._input, this.limits) {
    unawaited(_input.done.catchError((Object _) {
      _refuse('duplex_input_failed');
    }));
  }
  final IOSink _input;
  final BoundedDuplexLimits limits;
  final _frames = StreamController<List<int>>();
  final _settled = Completer<BoundedRunResult>();
  final _inputClosed = Completer<void>();
  final _partial = <int>[];
  Future<void> _writes = Future.value();
  void Function()? _stop;
  int _queued = 0;
  int _outputBytes = 0;
  int _inputBytes = 0;
  int _writeCount = 0;
  bool _closing = false;
  bool _outputDone = false;
  String? problem;

  /// A single consumer, bounded before decode/JSON parsing.
  Stream<List<int>> get output async* {
    await for (final frame in _frames.stream) {
      _queued--;
      yield frame;
    }
  }

  Future<BoundedRunResult> get settled => _settled.future;

  Future<void> send(List<int> bytes) {
    if (_closing || problem != null || _settled.isCompleted) {
      return Future.error(StateError('duplex_input_closed'));
    }
    if (bytes.any((byte) => byte < 0 || byte > 255) ||
        bytes.length > limits.maxFrameBytes ||
        (_inputBytes += bytes.length) > limits.maxInputBytes ||
        ++_writeCount > limits.maxWrites) {
      _refuse('duplex_input_budget_exceeded');
      return Future.error(StateError(problem!));
    }
    final captured = List<int>.unmodifiable(bytes);
    final write = _writes.then((_) async {
      if (_closing || problem != null) throw StateError('duplex_input_closed');
      _input.add(captured);
      await _input.flush();
    });
    _writes = write.catchError((Object _) {
      _refuse('duplex_input_failed');
    });
    return write;
  }

  /// StringSink projection for protocols that synchronously write packets.
  StringSink get input => _DuplexStringSink(this);

  /// Explicit stop, not merely EOF; physical result remains authoritative.
  Future<BoundedRunResult> close() {
    _stop?.call();
    unawaited(_closeInput());
    return settled;
  }

  Future<void> _closeInput() async {
    if (_closing) return _inputClosed.future;
    _closing = true;
    try {
      await _writes;
      await _input.close();
    } on Object {
      problem ??= 'duplex_input_close_failed';
    } finally {
      if (!_inputClosed.isCompleted) _inputClosed.complete();
    }
  }

  void _refuse(String reason) {
    problem ??= reason;
    _stop?.call();
    unawaited(_closeInput());
  }

  void _receive(List<int> bytes) {
    if (problem != null || _outputDone) return;
    if ((_outputBytes += bytes.length) > limits.maxOutputBytes) {
      _refuse('duplex_output_budget_exceeded');
      return;
    }
    for (final byte in bytes) {
      _partial.add(byte);
      if (_partial.length > limits.maxFrameBytes) {
        _refuse('duplex_frame_budget_exceeded');
        return;
      }
      if (byte == 10) {
        if (++_queued > limits.maxQueuedFrames) {
          _refuse('duplex_frame_backlog_exceeded');
          return;
        }
        _frames.add(List<int>.unmodifiable(_partial));
        _partial.clear();
      }
    }
  }

  void _outputClosed() {
    if (_outputDone) return;
    _outputDone = true;
    if (_partial.isNotEmpty) _refuse('duplex_incomplete_frame');
    unawaited(_frames.close());
  }
}

final class _DuplexStringSink implements StringSink {
  _DuplexStringSink(this.owner);
  final BoundedDuplexHandle owner;
  @override
  void write(Object? object) {
    unawaited(owner.send(utf8.encode('$object')).catchError((Object _) {}));
  }
  @override
  void writeln([Object? object = '']) => write('$object\n');
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));
  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}
