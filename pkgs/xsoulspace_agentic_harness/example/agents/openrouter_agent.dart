// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// REAL working agent over OpenRouter, built on the harness CLI SDK.
///
/// ```sh
/// cd pkgs/xsoulspace_agentic_harness
/// OPENROUTER_API_KEY=sk-or-... dart run example/agents/openrouter_agent.dart [--model m]
/// ```
///
/// Identical SDK surface as every other backend: fs tools jailed to the
/// current directory, write-confirmation gate, /situation /cancel /exit.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

Future<void> main(List<String> args) async {
  var model = args.contains('--model') ? args[args.indexOf('--model') + 1] : '';
  var apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';
  if (model.isEmpty) {
    final config = await EnvConfig.load();
    model = config.get('openrouter.model') ?? 'deepseek/deepseek-v4-flash-0731';
  }
  if (apiKey.isEmpty) {
    final config = await EnvConfig.load();
    apiKey = config.get('OPENROUTER_API_KEY') ?? '';
  }
  if (apiKey.isEmpty) {
    print('No OPENROUTER_API_KEY found (env or env_config).');
    exit(2);
  }

  final sharedRouter = ModelRouter(
    inferenceClientsBuilders: {
      OpenRouterModelNames.openRouter: () =>
          OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
    },
  );
  final suiteModelId = ModelId('agent-model');
  sharedRouter.models[suiteModelId] = Model(
    id: suiteModelId,
    name: OpenRouterModelNames.openRouter,
  );

  final cli = AgentCli(
    config: AgentCliConfig(
      title: 'xsoulspace-agent(openrouter:$model)',
      buildHandler: () => DefaultGenerationHandler(router: sharedRouter),
    ),
  );
  exit(await cli.run());
}
