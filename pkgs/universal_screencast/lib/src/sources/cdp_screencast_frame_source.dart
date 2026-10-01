import 'dart:async';
import 'dart:convert';

import 'package:universal_browser_cdp/universal_browser_cdp.dart';

import '../frame.dart';
import '../frame_source.dart';

/// Damage-driven frames straight from CDP's `Page.startScreencast`.
///
/// The browser pushes a frame only when the page repaints — an idle page
/// produces an idle stream. Every delivered frame is acknowledged with
/// `Page.screencastFrameAck`, which is the protocol's flow-control
/// contract; skipping acks stalls the stream.
class CdpScreencastFrameSource implements FrameSource {
  /// Creates the source over an attached page's [connection].
  ///
  /// [revisionProbe] supplies the current target revision (the CDP page
  /// facade bumps it on navigation).
  CdpScreencastFrameSource(
    this._connection, {
    int Function()? revisionProbe,
    this._format = 'jpeg',
    this._quality = 80,
  }) : _revisionProbe = revisionProbe ?? (() => 0);

  final CdpTransport _connection;
  final int Function() _revisionProbe;
  final String _format;
  final int _quality;
  final _frames = StreamController<Frame>.broadcast();
  StreamSubscription<CdpEvent>? _subscription;
  int _sequence = 0;
  bool _started = false;
  bool _stopped = false;

  @override
  String get id => 'cdp-screencast';

  @override
  SourceCapabilities get capabilities =>
      SourceCapabilities(contentTypes: [_contentType], damageDriven: true);

  String get _contentType => _format == 'png' ? 'image/png' : 'image/jpeg';

  @override
  Stream<Frame> start() {
    if (_stopped) throw StateError('CdpScreencastFrameSource is stopped');
    if (_started) return _frames.stream;
    _started = true;
    _subscription = _connection.on('Page.screencastFrame').listen((event) {
      final params = event.params;
      final data = params['data'];
      if (data is! String) return;
      final sessionId = params['sessionId'];
      unawaited(
        _connection.send('Page.screencastFrameAck', {'sessionId': ?sessionId}),
      );
      final metadata =
          params['metadata'] as Map<String, Object?>? ?? const {};
      final timestamp = metadata['timestamp'];
      _frames.add(
        Frame(
          sourceId: id,
          sequence: ++_sequence,
          revision: _revisionProbe(),
          bytes: base64Decode(data),
          contentType: _contentType,
          capturedAt: timestamp is num
              ? DateTime.fromMicrosecondsSinceEpoch(
                  (timestamp * 1e6).round(),
                  isUtc: true,
                )
              : DateTime.now().toUtc(),
        ),
      );
    }, onError: _frames.addError);
    unawaited(
      _connection.send('Page.startScreencast', {
        'format': _format,
        'quality': _quality,
        'everyNthFrame': 1,
      }),
    );
    return _frames.stream;
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _subscription?.cancel();
    if (!_connection.isClosed) {
      try {
        await _connection.send('Page.stopScreencast');
      } on Object {
        // The connection may be dying with the page; stop is best effort.
      }
    }
    await _frames.close();
  }
}
