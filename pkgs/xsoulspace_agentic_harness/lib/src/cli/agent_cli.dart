// ignore_for_file: lines_longer_than_80_chars

/// Provider-agnostic CLI SDK for the agent harness.
///
/// [AgentCli] composes world + tools + [CliHost] into an embeddable
/// everyday REPL. Providers never leak into this library: a backend is
/// injected as a [GenerationHandler] factory plus an optional availability
/// gate, so the same SDK drives OpenRouter, Apple Foundation Models, or a
/// scripted mock identically.
///
/// ```dart
/// final cli = AgentCli(
///   config: AgentCliConfig(
///     title: 'my-agent',
///     buildHandler: () => DefaultGenerationHandler(router: myRouter),
///   ),
/// );
/// await cli.run(); // blocks until /exit or EOF
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../agent.dart';
import '../tools/fs_tools.dart';

/// Injection point for a backend. Built once per session.
typedef HandlerFactory = GenerationHandler Function();

class AgentCliConfig {
  const AgentCliConfig({
    required this.buildHandler,
    this.title = 'xsoulspace-agent',
    this.availabilityGate,
    this.workspaceRoot,
    this.confirmationRequiredTools = const {'write'},
    this.requestToolConfirmation,
    this.systemPromptSuffix,
    this.extraPolicies = const [],
  });

  /// Display name used in banners/prompts.
  final String title;

  /// Builds the generation handler for this session (provider seam).
  final HandlerFactory buildHandler;

  /// Returns false when the backend cannot run on this device/session.
  /// When null, the backend is assumed available.
  final Future<bool> Function()? availabilityGate;

  /// Filesystem jail root for the read/write/list_dir tools (default cwd).
  final String? workspaceRoot;

  /// Tools requiring explicit approval before execution.
  final Set<String> confirmationRequiredTools;

  /// Approval callback for gated tools (defaults to a stdin y/N prompt when
  /// running interactively).
  final ToolConfirmationCallback? requestToolConfirmation;

  /// Appended to every actor's system prompt.
  final String? systemPromptSuffix;

  /// Extra decision policies appended to the default ReAct flow. Lets hosts
  /// configure baton-passing behavior (e.g. delegation to a peer agent on
  /// idle+goal) with the same one-line injection as [buildHandler], instead
  /// of subclassing or forking the engine.
  final List<DecisionPolicy> extraPolicies;
}

/// Embeddable everyday agent REPL. Owns no backend specifics.
class AgentCli {
  AgentCli({required this.config}) {
    _build();
  }

  final AgentCliConfig config;

  late final World world;
  late final CliHost host;
  late final Entity actor;

  bool _built = false;

  /// Reply sink for the current [run] session.
  StringSink? _replies;
  final _printedBeats = <String>{};

  void _build() {
    if (_built) return;
    _built = true;
    final root = config.workspaceRoot ?? Directory.current.path;
    world = World()
      ..addPlugin(AgentPlugin())
      ..upsertResource(ModelRouterResource(ModelRouter()))
      ..upsertResource(ToolRegistryResource());
    world.getResource<GenerationHandlerResource>().registerDefault(
          config.buildHandler(),
        );

    final registry = ToolRegistry();
    fsTools(FsToolsRoot(root)).forEach(registry.register);
    world.getResource<ToolRegistryResource>().register('default', registry);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorSystemPrompt(
        text: 'You are ${config.title}. '
            '${config.systemPromptSuffix ?? ''}'.trim(),
      ),
      PresentInScene(sceneEntity: scene),
    ]);
    world.flush();

    // Allow hosts to append decision policies (e.g. custom escalation /
    // delegation handoffs) to the default ReAct flow, the same way they can
    // inject a buildHandler.
    world.upsertResource(
      DecisionFlowResource(
        DecisionFlow([
          for (final p in DecisionFlow.defaultReAct().policies) p,
          for (final p in config.extraPolicies) p,
        ]),
      ),
    );

    final seen = <String>{};
    host = CliHost(
      world: world,
      requestToolConfirmation:
          config.requestToolConfirmation ?? _defaultConfirmation,
      config: CliHostConfig(
        confirmationRequiredTools: config.confirmationRequiredTools,
        onIdleTurnEnd: () async {
          // Surface completed beats as reply lines for non-streaming
          // backends; streaming backends already emitted deltas.
          for (final (facade, text) in world.query<TextContent>().toList()) {
            if (!seen.add(facade.entity.toJson())) continue;
            if (facade.has<IdentityBeat>()) continue;
            _replies?.writeln(text.text);
          }
        },
      ),
    );
  }

  static Future<bool> _defaultConfirmation(ToolName name, Object? args) async {
    stderr.write('approve ${name.value}($args)? [y/N] ');
    final line = stdin.readLineSync();
    return line?.trim().toLowerCase() == 'y';
  }

  /// Availability gate + REPL loop. Returns the process exit code.
  ///
  /// [input]/[output] are injectable for tests; defaults to stdin/stdout.
  Future<int> run({
    Stream<String>? input,
    StringSink? output,
  }) async {
    final out = output ?? stdout;
    if (config.availabilityGate != null &&
        !await config.availabilityGate!()) {
      out.writeln('${config.title}: backend unavailable on this device.');
      return 2;
    }

    _printedBeats.clear();
    _replies = out;
    unawaited(host.start());
    host.output.listen(out.write);

    out.writeln('${config.title} ready. Commands: /situation /cancel /exit');
    out.write('> ');

    final lines = input ?? stdinLines();
    await for (final line in lines) {
      switch (line.trim()) {
        case '':
          break;
        case '/exit':
        case '/quit':
          await host.stop();
          out.writeln('bye.');
          return 0;
        case '/cancel':
          host.cancel();
          out.writeln('(cancelled)');
        case '/situation':
          out.writeln(host.renderSituation());
        default:
          if (!host.feed(line)) out.writeln('(busy — /cancel first)');
      }
      out.write('> ');
    }
    await host.stop();
    return 0;
  }
}

Stream<String> stdinLines() =>
    stdin.transform(utf8.decoder).transform(const LineSplitter());
