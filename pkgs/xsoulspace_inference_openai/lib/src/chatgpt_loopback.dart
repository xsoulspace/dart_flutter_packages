import 'dart:async';
import 'dart:io';

import 'chatgpt_auth.dart';

/// Native desktop callback listener. The caller opens the system browser;
/// credentials and authorization URLs never enter an embedded web view.
final class ChatGptLoopback {
  ChatGptLoopback._(this._server)
    : redirectUri = Uri.parse('http://127.0.0.1:${_server.port}/auth/callback');
  final HttpServer _server;
  bool _used = false;
  Future<void>? _socketClose;
  void Function()? _cancel;
  ChatGptAuth? _auth;
  ChatGptAuthorizationAttempt? _attempt;
  final Uri redirectUri;

  static Future<ChatGptLoopback> bind() async =>
      ChatGptLoopback._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<ChatGptAccount> authorize({
    required ChatGptAuth auth,
    required String hostId,
    required String appName,
    required Future<void> Function(Uri) openBrowser,
    ChatGptAccount? account,
    ChatGptRegistration? registration,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (_used || _socketClose != null) {
      throw const ChatGptAuthException('listener_already_used');
    }
    _used = true;
    late ChatGptAuthorizationAttempt attempt;
    try {
      attempt = auth.begin(
        hostId: hostId,
        appName: appName,
        redirectUri: redirectUri,
        account: account,
        registration: registration,
      );
    } catch (_) {
      await _closeSocket();
      rethrow;
    }
    final completer = Completer<ChatGptAccount>();
    _auth = auth;
    _attempt = attempt;
    _cancel = () {
      unawaited(auth.cancelAuthorization(attempt).catchError((Object _) {}));
      if (!completer.isCompleted) {
        completer.completeError(
          const ChatGptAuthException('authorization_cancelled'),
        );
      }
    };
    var completing = false;
    final subscription = _server.listen((request) async {
      request.response.headers.set('Cache-Control', 'no-store');
      if (request.method != 'GET' ||
          request.uri.path != '/auth/callback' ||
          request.uri.queryParameters['state'] != attempt.state ||
          completing) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      completing = true;
      try {
        final result = await auth.complete(
          attempt,
          redirectUri.replace(query: request.uri.query),
        );
        if (!completer.isCompleted) completer.complete(result);
        request.response.write(
          'Sign-in complete. You may return to the application.',
        );
      } catch (error, stack) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          'Sign-in could not be completed. Return to the application.',
        );
        if (!completer.isCompleted) completer.completeError(error, stack);
      } finally {
        // The listener can time out while validation is in flight.
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    try {
      // Attach error handling before the browser can send the callback.
      final result = completer.future.timeout(
        timeout,
        onTimeout: () =>
            throw const ChatGptAuthException('authorization_expired'),
      );
      unawaited(
        Future<void>.sync(
          () => openBrowser(attempt.authorizationUri),
        ).catchError((Object error, StackTrace stack) {
          if (!completer.isCompleted) {
            completer.completeError(
              const ChatGptAuthException('browser_open_failed'),
              stack,
            );
          }
        }),
      );
      return await result;
    } finally {
      try {
        await auth.cancelAuthorization(attempt);
        await auth.settleAuthorization(attempt);
      } finally {
        await subscription.cancel();
        await _closeSocket();
      }
    }
  }

  Future<void> close() async {
    _cancel?.call();
    final attempt = _attempt;
    try {
      if (attempt != null) await _auth!.settleAuthorization(attempt);
    } finally {
      await _closeSocket();
    }
  }

  Future<void> _closeSocket() =>
      _socketClose ??= _server.close(force: true).then((_) {});
}
