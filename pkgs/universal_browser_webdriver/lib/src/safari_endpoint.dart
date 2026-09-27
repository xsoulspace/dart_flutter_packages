import 'dart:async';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'webdriver_client.dart';

/// Spawns and supervises `safaridriver`, macOS's bundled WebDriver
/// implementation for Safari (and WebKit views).
///
/// One-time setup: run `safaridriver --enable` as the target user. The
/// endpoint is an [owned] process — stop it on teardown; attaching to a
/// user-started safaridriver instead makes it [borrowed] and this class
/// is not the right tool (hand the URI to [WebDriverClient] directly).
class SafariDriverEndpoint {
  SafariDriverEndpoint._(this._process, this.client);

  final Process _process;
  bool _stopped = false;

  /// The WebDriver client bound to the spawned driver.
  final WebDriverClient client;

  /// Spawns `safaridriver -p <port>` and waits for `/status`.
  static Future<SafariDriverEndpoint> spawn({
    int port = 7051,
    String binary = 'safaridriver',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!Platform.isMacOS) {
      throw const DriverUnsupportedException('safaridriver only exists on macOS');
    }
    final process = await Process.start(binary, ['-p', '$port']);
    final serverUri = Uri.parse('http://127.0.0.1:$port');
    final client = WebDriverClient(serverUri);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final exitCheck = process.exitCode.then<bool>((code) => code != 0);
      if (await Future.any([exitCheck, Future<bool>.value(false)])) {
        throw const EndpointUnreachableException('safaridriver exited early');
      }
      try {
        await client.status();
        return SafariDriverEndpoint._(process, client);
      } on Object catch (error) {
        if (DateTime.now().isAfter(deadline)) {
          process.kill();
          throw EndpointUnreachableException(
            'safaridriver did not answer /status on port $port: $error',
            details: {'port': port},
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  /// Stops the driver process. Idempotent.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await client.deleteSession();
    _process.kill();
  }
}
