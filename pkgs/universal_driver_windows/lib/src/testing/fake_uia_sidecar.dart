import 'dart:async';
import 'dart:convert';

import 'package:universal_driver_windows/universal_driver_windows.dart';

/// In-memory `uia-sidecar/1` stand-in for tests on any platform.
final class FakeUiaSidecarTransport implements UiaSidecarTransport {
  final _controller = StreamController<String>.broadcast();
  final List<String> written = [];

  /// When set, the next request is answered with this error text.
  String? failNext;

  @override
  Stream<String> get lines => _controller.stream;

  /// Simulates the sidecar's handshake line.
  void serveHandshake() =>
      _controller.add(jsonEncode({'sidecar': 'uia-sidecar/1'}));

  /// Simulates an event.
  void emitEvent(String kind, Map<String, Object?> params) =>
      _controller.add(
        jsonEncode({'event': kind, ...params}),
      );

  @override
  Future<void> writeLine(String line) async {
    written.add(line);
    final message = jsonDecode(line) as Map<String, Object?>;
    final id = message['id'] as int?;
    final op = message['op'] as String?;
    if (id == null || op == null) return;
    if (failNext != null) {
      final error = failNext!;
      failNext = null;
      _controller.add(jsonEncode({'id': id, 'error': error}));
      return;
    }
    switch (op) {
      case 'snapshot':
        _controller.add(
          jsonEncode({
            'id': id,
            'result': {
              'root': {
                'id': 0,
                'name': 'window',
                'controlType': 50025,
                'children': [
                  {'id': 1, 'name': 'OK', 'controlType': 50000},
                ],
              },
            },
          }),
        );
      default:
        _controller.add(
          jsonEncode({
            'id': id,
            'result': {'ok': op},
          }),
        );
    }
  }

  @override
  Future<void> kill() async {
    await _controller.close();
  }
}
