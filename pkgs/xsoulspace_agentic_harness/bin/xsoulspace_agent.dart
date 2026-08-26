import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// The real working agent entrypoint.
///
/// Provider-agnostic by design: backends register themselves here. The
/// built-in `mock` backend keeps the binary runnable anywhere (CI, demos);
/// real backends ship as thin launchers in their provider packages
/// (e.g. `apple_foundation`'s `bin/agent.dart`) or via
/// `example/agents/openrouter_agent.dart` for OpenRouter.
Future<void> main(List<String> args) async {
  final backend =
      args.contains('--backend') ? args[args.indexOf('--backend') + 1] : 'mock';
  switch (backend) {
    case 'mock':
      final cli = AgentCli(
        config: AgentCliConfig(
          title: 'xsoulspace-agent(mock)',
          buildHandler: () => ScriptedGenerationHandler(const [
            ScriptedTurn(text: 'ok'),
          ]),
        ),
      );
      // ignore: avoid_print
      exit(await cli.run());
    default:
      // ignore: avoid_print
      print(
        'Unknown backend "$backend". Harness ships mock; real backends '
        '(openrouter, apple-foundation) launch from their provider '
        'packages — see example/agents/openrouter_agent.dart.',
      );
      exit(2);
  }
}
