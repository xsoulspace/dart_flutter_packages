import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../frame.dart';
import '../frame_sink.dart';

/// A loopback HTTP server streaming an MJPEG multipart body, viewable in
/// any browser via `<img src="http://127.0.0.1:PORT/stream">` — the
/// zero-dependency human viewer.
///
/// Accepts JPEG frames only; composition validation refuses pairing it
/// with a PNG-only source before anything starts.
class MjpegHttpSink implements FrameSink {
  /// Creates an unstarted MJPEG sink.
  MjpegHttpSink({InternetAddress? address, this._port})
    : _address = address ?? InternetAddress.loopbackIPv4;

  final InternetAddress _address;
  final int? _port;
  final List<HttpResponse> _streams = [];
  HttpServer? _server;
  bool _closed = false;

  @override
  String get id => 'mjpeg';

  @override
  List<String> get acceptedContentTypes => const ['image/jpeg'];

  /// Binds the server; returns the stream URL for `<img>` tags.
  Future<Uri> start() async {
    if (_server != null) return streamUri;
    _server = await HttpServer.bind(_address, _port ?? 0);
    _server!.listen((request) => _handle(request).catchError((Object _) {}));
    return streamUri;
  }

  /// The multipart stream URL.
  Uri get streamUri {
    final server = _server;
    if (server == null) throw StateError('MjpegHttpSink is not started');
    return Uri.parse('http://127.0.0.1:${server.port}/stream');
  }

  @override
  Future<void> push(Frame frame) async {
    if (_closed) throw SinkClosedException(id);
    if (frame.contentType != 'image/jpeg') {
      throw ProtocolException(
        'MjpegHttpSink only accepts image/jpeg frames',
        details: {'contentType': frame.contentType},
      );
    }
    final header =
        '--frame\r\n'
        'Content-Type: image/jpeg\r\n'
        'Content-Length: ${frame.bytes.length}\r\n\r\n';
    for (final response in List.of(_streams)) {
      response.add(utf8.encode(header));
      response.add(frame.bytes);
      response.add(utf8.encode('\r\n'));
      unawaited(response.flush());
    }
  }

  @override
  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    for (final response in List.of(_streams)) {
      await response.close();
    }
    _streams.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != '/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/x-mixed-replace; boundary=frame',
    );
    response.headers.set(
      HttpHeaders.cacheControlHeader,
      'no-cache, private',
    );
    _streams.add(response);
    // dart:io's HttpClient completes the request only when the first body
    // chunk arrives, so the boundary preamble goes out immediately.
    response.add(utf8.encode('--frame\r\n'));
    await response.flush();
    // Park the handler until the stream ends: dart:io closes the response
    // as soon as the handler's future completes.
    await response.done.catchError((Object _) {});
  }
}
