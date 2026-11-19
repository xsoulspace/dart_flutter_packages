import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_xai/xsoulspace_inference_xai.dart';

void main() {
  test('a responses call returns text and a function call', () async {
    final api = await _Api.start();
    final store = _MemoryStore()
      ..records['user-1'] = GrokAccount(
        clientId: 'la-client',
        subject: 'user-1',
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        idToken: 'unused',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        scopes: {'api:access'},
      );
    final auth = GrokAuth(
      store: store,
      registration: LastAnswerGrokRegistration(
        clientId: 'la-client',
        apiBase: 'http://127.0.0.1:${api.port}/v1',
      ),
    );
    final client = GrokResponsesClient(
      auth: auth,
      subject: 'user-1',
      model: 'grok-test',
      client: http.Client(),
    );
    final result = await client.infer(
      InferenceRequest(
        prompt: 'Read the note.',
        reasoningEffort: 'low',
      ),
    );
    expect(result.success, isTrue);
    expect(result.data!.presentationText, 'Ready.');
    expect(result.data!.toolCalls.single.name.value, 'read_note');
    expect(result.data!.toolCalls.single.arguments, {'path': 'note.md'});
    expect(api.body['model'], 'grok-test');
    expect(api.body['reasoning'], {'effort': 'low'});
    expect(api.authorization, 'Bearer access-1');
    client.close();
    auth.close();
    await api.close();
  });

  test('an unknown reasoning effort is refused before the network', () async {
    final auth = GrokAuth(
      store: _MemoryStore(),
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
    );
    final client = GrokResponsesClient(
      auth: auth,
      subject: 'user-1',
      model: 'grok-test',
    );
    final result = await client.infer(
      InferenceRequest(prompt: 'Hi', reasoningEffort: 'xhigh'),
    );
    expect(result.error?.code, 'reasoning_effort_unsupported');
    client.close();
    auth.close();
  });
}

final class _MemoryStore implements GrokCredentialStore {
  final records = <String, GrokAccount>{};
  @override
  Future<GrokAccount?> read(String subject) async => records[subject];
  @override
  Future<void> write(GrokAccount account) async =>
      records[account.subject] = account;
  @override
  Future<void> removeTokens(String subject) async => records.remove(subject);
}

final class _Api {
  _Api._(this._server);
  final HttpServer _server;
  Map<String, dynamic> body = const {};
  String? authorization;
  int get port => _server.port;

  static Future<_Api> start() async {
    final api = _Api._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    api._server.listen((request) async {
      api.authorization = request.headers.value('authorization');
      api.body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'resp-1',
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Ready.'},
              ],
            },
            {
              'type': 'function_call',
              'name': 'read_note',
              'call_id': 'call-1',
              'arguments': '{"path":"note.md"}',
            },
          ],
          'usage': {'input_tokens': 3, 'output_tokens': 2},
        }),
      );
      await request.response.close();
    });
    return api;
  }

  Future<void> close() => _server.close(force: true);
}
