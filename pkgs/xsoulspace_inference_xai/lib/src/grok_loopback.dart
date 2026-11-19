import 'dart:async';
import 'dart:io';

import 'grok_auth.dart';
import 'grok_registration.dart';

/// Loopback listener pinned to the redirect xAI must register.
/// A busy port refuses. Another port would not match the registration.
final class GrokLoopback {
  GrokLoopback._(this._server);
  final HttpServer _server;
  bool _used = false;
  bool _closed = false;
  GrokAuthorizationAttempt? _attempt;

  static Future<GrokLoopback> bind() async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        LastAnswerGrokRegistration.redirectPort,
      );
      return GrokLoopback._(server);
    } on SocketException {
      throw const GrokAuthException('redirect_port_busy');
    }
  }

  Future<GrokAccount> authorize({
    required GrokAuth auth,
    required Future<void> Function(Uri uri) openBrowser,
    String? expectedSubject,
    String? loginHint,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (_used) throw const GrokAuthException('listener_already_used');
    _used = true;
    final attempt = auth.begin(
      expectedSubject: expectedSubject,
      loginHint: loginHint,
    );
    _attempt = attempt;
    final completer = Completer<GrokAccount>();
    var completing = false;
    final subscription = _server.listen((request) async {
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.contentType = ContentType.html;
      final remote = request.connectionInfo?.remoteAddress;
      final allowed = remote == InternetAddress.loopbackIPv4;
      if (!allowed ||
          request.method != 'GET' ||
          request.uri.path != '/callback' ||
          completing) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(_page('Sign-in was not accepted.'));
        await request.response.close();
        return;
      }
      completing = true;
      try {
        final result = await auth.complete(
          attempt,
          attempt.redirectUri.replace(query: request.uri.query),
        );
        if (!completer.isCompleted) completer.complete(result);
        request.response.write(
          _page('Sign-in complete. You can return to Last Answer.'),
        );
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(_page('Sign-in was not accepted.'));
      } finally {
        await request.response.close();
      }
    });
    try {
      await openBrowser(attempt.authorizationUri);
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const GrokAuthException('authorization_expired'),
      );
    } finally {
      await subscription.cancel();
      await close();
    }
  }

  Future<void> close() async {
    _attempt?.cancelled = true;
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }
}

String _page(String text) =>
    '<!doctype html><html><body><p>$text</p></body></html>';
