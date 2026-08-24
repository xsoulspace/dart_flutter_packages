import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_acp/xsoulspace_inference_acp.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Absolute path to the acp_toolkit checkout (sibling repo).
final _toolkitDir =
    '/Users/antonio/mcp/cline/intentcall/packages/acp_toolkit';

Future<void> main() async {
  late AcpInferenceClient client;

  setUpAll(() async {
    client = AcpInferenceClient(
      command: 'dart',
      arguments: ['run', 'bin/acp_server.dart', '--backend', 'echo'],
      workingDirectory: _toolkitDir,
    );
  });

  tearDownAll(() async {
    await client.dispose();
  });

  test('echo agent is available and answers a prompt turn', () async {
    final available = await client.refreshAvailability();
    expect(available, isTrue, reason: 'echo agent should spawn and initialize');

    final result = await client.infer(
      InferenceRequest(prompt: 'hello world', workingDirectory: '/tmp'),
    );
    expect(result.success, isTrue, reason: '${result.error}');
    expect(
      result.data?.meta['stopReason'],
      anyOf('end_turn', equals('end_turn')),
    );
    expect(result.data?.meta['sessionId'], isNotEmpty);
  });
}
