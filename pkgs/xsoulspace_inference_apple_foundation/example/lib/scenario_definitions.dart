// ignore_for_file: lines_longer_than_80_chars

/// Built-in stress scenarios for the Apple Foundation headless harness.
///
/// Start simple, escalate: single topic, then multi-topic, then multi-actor +
/// tools + dynamic tool registration. Each scenario is a [Scenario] consumed
/// by `ScenarioRunner` via the CLI (`main_stress_cli.dart`).
///
/// Tools are the *real* shared definitions from core (`fsTools(root)`) plus
/// example-specific clock/search tools, all built with structured schemas.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A small "current time" tool the actors can use when a decision mentions
/// date/time. Registered statically (part of [Scenario].tools).
ToolDef clockTool() => ToolDef.encode(
  name: const ToolName('clock'),
  description: 'Returns the current date and time.',
  argsSchema: SchemaBundle(
    root: FM.object(
      'ClockResult',
      properties: () => [FM.prop('iso', FM.string())],
    ),
  ),
  execute: (args) async => <String, dynamic>{
    'iso': DateTime.now().toIso8601String(),
  },
);

/// A "web search" tool added lazily by [Scenario.toolHook] — exercises the
/// dynamic tool-registration path (register a new tool when a decision needs
/// it).
ToolDef searchTool() => ToolDef.encode(
  name: const ToolName('web_search'),
  description: 'Searches the web (simulated) and returns a short summary.',
  argsSchema: SchemaBundle(
    root: FM.object(
      'SearchResult',
      properties: () => [
        FM.prop('query', FM.string()),
        FM.prop('summary', FM.string()),
      ],
    ),
  ),
  execute: (args) async {
    final query = (args as Map?)?['query'];
    return <String, dynamic>{
      'query': query?.toString() ?? '',
      'summary': 'Simulated result for "$query".',
    };
  },
);

/// A coding-agent stress scenario: multi-actor, multi-topic, real file-system
/// tools (from core), plus clock + a dynamically-added search tool.
Scenario multiActorTopicScenario() => Scenario(
  name: 'multi_actor_multi_topic',
  // Real shared file-system tools for the coding agent, jailed to a
  // scratch directory so the model cannot touch anything outside it.
  tools: [...fsTools(FsToolsRoot('/tmp/ecsly_stress_workspace')), clockTool()],
  // Dynamically add the search tool before the run.
  toolHook: () async => [searchTool()],
  maxConcurrent: 2,
  actors: [
    ScenarioActor(
      name: 'coder',
      systemPrompt:
          'You are a focused coding agent. Be terse. Use tools when asked. '
          'Think step by step but do not repeat context.',
      decisions: [
        'Read the file /tmp/hello.txt and report its contents.',
        'What is the current date? Use the clock tool.',
        'Summarize what you know about parsers in one sentence.',
      ],
    ),
    ScenarioActor(
      name: 'researcher',
      systemPrompt:
          'You are a research assistant. Use web_search for unfamiliar topics. '
          'Answer in 1-2 sentences.',
      decisions: [
        'What is the current time? Use a tool if helpful.',
        'Look up the latest info on vector databases.',
      ],
    ),
  ],
);
