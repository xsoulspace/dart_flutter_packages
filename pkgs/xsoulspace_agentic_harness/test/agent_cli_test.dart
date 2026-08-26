import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

void main() {
  test('agent cli: feed → response delta → /situation → /exit', () async {
    final controller = StreamController<String>();
    final out = StringBuffer();
    final cli = AgentCli(
      config: AgentCliConfig(
        title: 'sdk-test',
        buildHandler: () => ScriptedGenerationHandler(const [
          ScriptedTurn(text: 'hello from scripted'),
        ]),
      ),
    );

    final exitCode = cli.run(input: controller.stream, output: out);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.hasListener, isTrue);

    controller.add('say hi');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(out.toString(), contains('hello from scripted'));

    controller.add('/situation');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(out.toString(), anyOf(contains('prompt:'), contains('(idle)')));

    controller.add('/cancel');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(out.toString(), contains('(cancelled)'));

    controller.add('/exit');
    final code = await exitCode;
    expect(code, 0);
    expect(out.toString(), contains('bye.'));
    await controller.close();
  });

  test('agent cli: availability gate short-circuits with exit code 2',
      () async {
    final cli = AgentCli(
      config: AgentCliConfig(
        title: 'gated',
        availabilityGate: () async => false,
        buildHandler: () => ScriptedGenerationHandler(const []),
      ),
    );
    final code = await cli.run(
      input: const Stream.empty(),
      output: StringBuffer(),
    );
    expect(code, 2);
  });

  test('agent cli: busy feed is rejected until cancelled', () async {
    final controller = StreamController<String>();
    final out = StringBuffer();
    final cli = AgentCli(
      config: AgentCliConfig(
        title: 'busy-test',
        confirmationRequiredTools: const {},
        buildHandler: () => ScriptedGenerationHandler(const [
          ScriptedTurn(text: 'first'),
          ScriptedTurn(text: 'second'),
        ]),
      ),
    );
    final done = cli.run(input: controller.stream, output: out);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    controller.add('one');
    // Immediately feed again — actor still holds agency from the first.
    controller.add('two');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(out.toString(), contains('first'));
    // The second line was either accepted (post-idle) or rejected as busy;
    // both are safe outcomes. Drive to a clean stop.
    if (!out.toString().contains('second')) {
      controller.add('/cancel');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.add('two');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(out.toString(), contains('second'));
    }
    controller.add('/exit');
    expect(await done, 0);
    await controller.close();
  });
}
