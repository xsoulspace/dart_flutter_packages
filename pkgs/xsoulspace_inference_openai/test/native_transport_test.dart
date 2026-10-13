import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';
import 'support.dart';

/// Test-only wire redirection, preserving native HTTP cancellation behavior.
final class LocalTransport extends http.BaseClient {
  LocalTransport(this.port);
  final int port;
  final inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest original) {
    final request =
        http.AbortableRequest(
            original.method,
            Uri.parse('http://127.0.0.1:$port/'),
            abortTrigger: original is http.AbortableRequest
                ? original.abortTrigger
                : null,
          )
          ..headers.addAll(original.headers)
          ..body = (original as http.Request).body;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

final class WaitingCredentials implements ChatGptCredentialStore {
  final waiting = Completer<ChatGptAccount?>();
  @override
  Future<ChatGptAccount?> read(String clientId) => waiting.future;
  @override
  Future<void> write(ChatGptAccount account) async {}
  @override
  Future<void> removeTokens(String clientId) async {}
}

void main() {
  for (final cancel in [true, false]) {
    test(
      'stalled HTTP error body settles on ${cancel ? 'cancel' : 'deadline'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final transport = LocalTransport(server.port);
        final store = MemoryCredentials();
        await store.write(account());
        final auth = ChatGptAuth(store: store);
        final started = Completer<void>();
        final requests = server.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = 400;
          request.response.write('{"error":');
          await request.response.flush();
          started.complete();
        });
        addTearDown(() async {
          transport.close();
          auth.close();
          await requests.cancel();
          await server.close(force: true);
        });
        final receipts = <ResponsesDecisionReceipt>[];
        final provider = OpenAiResponsesClient(
          auth: auth,
          clientId: 'oaiapp_test',
          model: 'fixture',
          client: transport,
          observeDecision: receipts.add,
          deadline: Duration(milliseconds: cancel ? 2000 : 250),
        );
        final pending = provider.infer(InferenceRequest(prompt: 'question'));
        await started.future.timeout(const Duration(seconds: 1));
        if (cancel) provider.cancelActive();
        final result = await pending.timeout(const Duration(seconds: 1));
        expect(
          result.error!.code,
          cancel ? 'inference_cancelled' : 'inference_timeout',
        );
        await provider.settleActive().timeout(const Duration(seconds: 1));
        expect(receipts, hasLength(1));
        final receipt = receipts.single;
        expect(
          receipt.outcome,
          cancel ? 'inference_cancelled' : 'inference_timeout',
        );
        // Server flush does not prove headers were observed before interruption.
        expect(receipt.httpStatus, anyOf(isNull, 400));
        expect(receipt.parsedToolCalls, 0);
        expect(receipt.parsedTextChars, 0);
      },
    );
  }
  test(
    'deadline detaches from stalled shared auth without late inference dispatch',
    () async {
      final store = WaitingCredentials();
      final auth = ChatGptAuth(store: store);
      var calls = 0;
      final provider = OpenAiResponsesClient(
        auth: auth,
        clientId: 'oaiapp_test',
        model: 'fixture',
        deadline: const Duration(milliseconds: 50),
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      final result = await provider
          .infer(InferenceRequest(prompt: 'next'))
          .timeout(const Duration(seconds: 1));
      expect(result.error!.code, 'inference_timeout');
      store.waiting.complete(account());
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      auth.close();
    },
  );
  test(
    'native HTTP cancel settles while server is stalled mid stream',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = LocalTransport(server.port);
      final store = MemoryCredentials();
      await store.write(account());
      final auth = ChatGptAuth(store: store);
      final receipts = <ResponsesDecisionReceipt>[];
      final provider = OpenAiResponsesClient(
        auth: auth,
        clientId: 'oaiapp_test',
        model: 'fixture',
        client: transport,
        observeDecision: receipts.add,
        deadline: const Duration(seconds: 2),
      );
      final started = Completer<void>();
      final requests = server.listen((request) async {
        await request.drain<void>();
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"type":"response.output_item.done","output_index":0,'
          '"item":{"type":"message","status":"completed","content":'
          '[{"type":"output_text","text":"first-final"}]}}\n\n'
          'data: {"type":"response.output_text.delta","output_index":1,'
          '"delta":"second-partial"}\n\n',
        );
        await request.response.flush();
        started.complete();
      });
      addTearDown(() async {
        transport.close();
        auth.close();
        await requests.cancel();
        await server.close(force: true);
      });
      final session = await provider.streamStructuredText(
        InferenceRequest(prompt: 'question'),
      );
      final receivedPartial = Completer<void>();
      final events = session.events.map((event) {
        if (event.textDelta != null && !receivedPartial.isCompleted) {
          receivedPartial.complete();
        }
        return event;
      }).toList();
      await started.future;
      await receivedPartial.future.timeout(const Duration(seconds: 1));
      await session.cancel();
      expect((await session.result).error!.code, 'inference_cancelled');
      await session.dispose().timeout(const Duration(seconds: 1));
      await events;
      expect(receipts, hasLength(1));
      expect(receipts.single.outcome, 'inference_cancelled');
      expect(receipts.single.streamedDoneItems, 1);
      expect(receipts.single.parsedTextChars, 0);
      expect(receipts.single.parsedToolCalls, 0);
    },
  );

  test('native HTTP deadline settles a stalled request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = LocalTransport(server.port);
    final store = MemoryCredentials();
    await store.write(account());
    final auth = ChatGptAuth(store: store);
    final requests = server.listen((request) async {
      await request.drain<void>();
    });
    addTearDown(() async {
      transport.close();
      auth.close();
      await requests.cancel();
      await server.close(force: true);
    });
    final provider = OpenAiResponsesClient(
      auth: auth,
      clientId: 'oaiapp_test',
      model: 'fixture',
      client: transport,
      deadline: const Duration(milliseconds: 80),
    );
    final result = await provider.infer(InferenceRequest(prompt: 'question'));
    expect(result.error!.code, 'inference_timeout');
  });

  test(
    'loopback rejects unsolicited callback then handles browser denial',
    () async {
      var exchanges = 0;
      final auth = ChatGptAuth(
        store: MemoryCredentials(),
        client: MockClient((_) async {
          exchanges++;
          return http.Response('{}', 200);
        }),
      );
      final listener = await ChatGptLoopback.bind();
      final browser = http.Client();
      addTearDown(browser.close);
      final result = listener.authorize(
        auth: auth,
        hostId: account().hostId,
        appName: 'Last Answer',
        openBrowser: (url) async {
          final unsolicited = await browser.get(
            listener.redirectUri.replace(
              queryParameters: {'state': 'wrong', 'code': 'unsolicited'},
            ),
          );
          expect(unsolicited.statusCode, 400);
          await browser.get(
            listener.redirectUri.replace(
              queryParameters: {
                'state': url.queryParameters['state']!,
                'error': 'access_denied',
              },
            ),
          );
        },
      );
      await expectLater(
        result,
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'authorization_declined',
          ),
        ),
      );
      expect(exchanges, 0);
    },
  );

  test(
    'browser launch error closes the listener without uncaught future errors',
    () async {
      final listener = await ChatGptLoopback.bind();
      final auth = ChatGptAuth(store: MemoryCredentials());
      addTearDown(auth.close);
      await expectLater(
        listener.authorize(
          auth: auth,
          hostId: account().hostId,
          appName: 'Last Answer',
          openBrowser: (_) async => throw StateError('private path'),
        ),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'browser_open_failed',
          ),
        ),
      );
      final browser = http.Client();
      addTearDown(browser.close);
      await expectLater(
        browser.get(listener.redirectUri),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('response size is bounded even before an SSE event delimiter', () async {
    final store = MemoryCredentials();
    await store.write(account());
    final auth = ChatGptAuth(store: store);
    addTearDown(auth.close);
    final provider = OpenAiResponsesClient(
      auth: auth,
      clientId: 'oaiapp_test',
      model: 'fixture',
      maxResponseBytes: 32,
      client: MockClient((_) async => http.Response('data: ${'x' * 100}', 200)),
    );
    expect(
      (await provider.infer(InferenceRequest(prompt: 'question'))).error!.code,
      'response_too_large',
    );
  });
}
