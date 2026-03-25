import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  FakeWebSocketChannel({this.protocolValue}) {
    _outgoingSubscription = _outgoingController.stream.listen(sentMessages.add);
    _readyCompleter.complete();
  }

  final String? protocolValue;
  final Completer<void> _readyCompleter = Completer<void>();
  final StreamController<dynamic> _incomingController =
      StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _outgoingController =
      StreamController<dynamic>.broadcast();
  late final StreamSubscription<dynamic> _outgoingSubscription;

  final List<dynamic> sentMessages = <dynamic>[];

  int? _closeCode;
  String? _closeReason;
  bool _closed = false;

  @override
  String? get protocol => protocolValue;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(
    outgoingSink: _outgoingController.sink,
    closeImpl: _closeSink,
    done: _outgoingController.done,
  );

  void emitServerMessage(final Object message) {
    if (!_incomingController.isClosed) {
      _incomingController.add(message);
    }
  }

  Future<void> closeFromServer([final int? code, final String? reason]) async {
    _closeCode = code;
    _closeReason = reason;
    await _closeSink(code, reason);
  }

  Future<void> dispose() async {
    await _closeSink(null, null);
    await _outgoingSubscription.cancel();
  }

  Future<void> _closeSink(final int? code, final String? reason) async {
    if (_closed) {
      return;
    }

    _closed = true;
    _closeCode = code;
    _closeReason = reason;
    await _outgoingController.close();
    await _incomingController.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink({
    required final StreamSink<dynamic> outgoingSink,
    required final Future<void> Function(int?, String?) closeImpl,
    required final Future<void> done,
  }) : _outgoingSink = outgoingSink,
       _closeImpl = closeImpl,
       _done = done;

  final StreamSink<dynamic> _outgoingSink;
  final Future<void> Function(int?, String?) _closeImpl;
  final Future<void> _done;

  @override
  Future<void> get done => _done;

  @override
  void add(final dynamic data) {
    _outgoingSink.add(data);
  }

  @override
  Future<void> addStream(final Stream<dynamic> stream) =>
      _outgoingSink.addStream(stream);

  @override
  void addError(final Object error, [final StackTrace? stackTrace]) {
    _outgoingSink.addError(error, stackTrace);
  }

  @override
  Future<void> close([final int? closeCode, final String? closeReason]) =>
      _closeImpl(closeCode, closeReason);
}
