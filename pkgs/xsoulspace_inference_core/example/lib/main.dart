import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final brightness = hour < 12 || hour > 18
        ? Brightness.dark
        : Brightness.light;
    return MaterialApp(
      title: 'Agent Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        ),
      ),
      home: const MyHomePage(title: 'Agent Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// ECS-based scenario that runs the agent harness loop.
class EcsScenario {
  final World world;
  final DefaultActorGenerateHandler handler;
  final HarnessLoop loop;
  final Entity actorEntity;
  final ToolRegistry toolRegistry;

  EcsScenario({
    required this.world,
    required this.handler,
    required this.loop,
    required this.actorEntity,
    required this.toolRegistry,
  });

  void dispose() {
    loop.stop();
    world.clear();
  }

  /// Get the last model response from the actor's memories.
  String? get lastResponse {
    final memories = world.maybeGetComponent<ActorRuntimeMemories>(actorEntity);
    if (memories == null || memories.fragments.isEmpty) return null;
    final last = memories.fragments.last;
    if (last.type == ContextFragmentType.modelResponse) {
      final beatEntity = world.getEntity(last.beat).$1;
      final textContent = beatEntity.get<TextContent>();
      return textContent?.text;
    }
    return null;
  }
}

/// Build an ECS world with the agent plugin and a scene + actor.
Future<EcsScenario> buildEcsScenario({
  required ToolRegistry toolRegistry,
  required String systemPrompt,
  required String openDecisionPrompt,
}) async {
  final world = World()..addPlugin(AgentPlugin());

  final router = ModelRouter(
    inferenceClientsBuilders: {
      DefaultModelNames.appleFoundation: () => AppleFoundationInferenceClient(
        api: AppleFoundationInferenceClient.initApi(),
      ),
    },
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..flush();

  // Register the tool registry
  final toolResource = world.getResource<ToolRegistryResource>();
  toolResource.register('default', toolRegistry);

  // Register the default handler
  final handler = DefaultActorGenerateHandler()..router = router;

  // Spawn a scene
  final sceneEntity = world.spawnComponents([const Scene(), SceneFrame()]);

  // Spawn an actor with a goal
  final actorId = AgentId.create();
  final modelId = ModelId.create();
  final actorEntity = world.spawnComponents([
    Actor(agentId: actorId),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: systemPrompt),
    ActorRuntimeMemories(),
    PresentInScene(sceneEntity: sceneEntity),
    const ActorTools(registryName: 'default'),
  ]);

  // Create an open decision — this triggers the agency loop
  world.upsertComponent(actorEntity, OpenDecision(prompt: openDecisionPrompt));
  world.flush();

  // Create the harness loop
  final loop = HarnessLoop(world: world, handler: handler);

  return EcsScenario(
    world: world,
    handler: handler,
    loop: loop,
    actorEntity: actorEntity,
    toolRegistry: toolRegistry,
  );
}

class _MyHomePageState extends State<MyHomePage> {
  final _messages = ImmutableOrderedList<String>();
  final TextEditingController _controller = TextEditingController();

  String get _txt => _controller.text;

  bool _isRunning = false;
  int _scenarioIndex = 0;
  EcsScenario? _currentScenario;

  // Tool registry for scenario 3 (weather tool)
  final _toolRegistry = ToolRegistry()
    ..register(
      ToolDef.structured(
        name: ToolName('getWeatherForHour'),
        description: 'Returns weather for a specific hour of today',
        parameters: SchemaBundle(
          root: FM.object(
            'time',
            properties: () => [
              FM.prop('hour', FM.double(guides: [RangeGuide(0, 23)])),
            ],
          ),
        ),
        execute: (args) async {
          final params = jsonDecodeMapAs(args);
          final hour = jsonDecodeInt(params['hour']);
          final (temp, condition) = switch (hour) {
            < 4 => (16, 'rain'),
            >= 4 && < 12 => (20, 'sunny'),
            >= 12 && < 21 => (20, 'cloudy'),
            _ => (16, 'sunny'),
          };
          return jsonEncode({
            'hour': hour,
            'temp': temp,
            'condition': condition,
          });
        },
      ),
    );

  List<(String, int)> get _scenarios => [
    ('one-text', 0),
    ('h -> llm -> h -> llm', 1),
    ('scheme + tool call: Weather', 2),
  ];

  void _switchToScenario(int? index) {
    if (index == null || _scenarioIndex == index) return;
    _cleanup();
    setState(() => _scenarioIndex = index);
  }

  void _cleanup() {
    _messages.clear();
    _currentScenario?.dispose();
    _currentScenario = null;
  }

  void _setLoading() => setState(() {
    _isRunning = true;
  });

  Future<void> _runScenario() async {
    _setLoading();
    _cleanup();

    final scenario = _scenarios[_scenarioIndex].$2;
    final systemPrompt = '';
    final openDecision = switch (scenario) {
      0 => 'Reply with one short word: hello.',
      1 => 'Continue the conversation with: "Tell me about yourself.".',
      2 => 'What is the weather at hour 14?',
      _ => 'Reply with one short word: hello.',
    };

    try {
      final ecsScenario = await buildEcsScenario(
        toolRegistry: scenario == 2 ? _toolRegistry : ToolRegistry(),
        systemPrompt: systemPrompt,
        openDecisionPrompt: openDecision,
      );

      _currentScenario = ecsScenario;

      // Start the harness loop — runs for 10 seconds
      ecsScenario.loop.start(
        until: Future.delayed(const Duration(seconds: 10)),
      );

      // Wait for the loop to process
      await Future.delayed(const Duration(seconds: 5));

      final response = ecsScenario.lastResponse;
      setState(() {
        _messages
          ..add(_txt)
          ..add(response ?? 'No response received');
        _controller.clear();
        _isRunning = false;
      });
    } catch (e, st) {
      log('scenario | try failure', error: e, stackTrace: st);
      setState(() {
        _messages
          ..add(_txt)
          ..add('Error: $e');
        _controller.clear();
        _isRunning = false;
      });
    }
  }

  Future<void> _reply() async {
    if (_currentScenario == null) return;
    _setLoading();

    final scenario = _scenarios[_scenarioIndex].$2;

    try {
      // Add a new OpenDecision to the existing actor
      final actor = _currentScenario!.actorEntity;
      final prompt = switch (scenario) {
        1 => 'Continue: $_txt',
        2 => 'Weather at hour 8?',
        _ => _txt,
      };

      _currentScenario!.world.upsertComponent(
        actor,
        OpenDecision(prompt: prompt),
      );
      _currentScenario!.world.flush();

      // Wait for the loop to process
      await Future.delayed(const Duration(seconds: 5));

      final response = _currentScenario!.lastResponse;
      setState(() {
        _messages
          ..add(_txt)
          ..add(response ?? 'No response received');
        _controller.clear();
        _isRunning = false;
      });
    } catch (e, st) {
      log('reply | try failure', error: e, stackTrace: st);
      setState(() {
        _messages
          ..add(_txt)
          ..add('Error: $e');
        _controller.clear();
        _isRunning = false;
      });
    }
  }

  void _onReply() {
    if (_currentScenario != null &&
        _currentScenario!.world.getEntity(_currentScenario!.actorEntity).$2) {
      _reply();
    } else {
      _runScenario();
    }
  }

  @override
  void dispose() {
    _cleanup();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 4,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    return Text(_messages[index]);
                  },
                  itemCount: _messages.length,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('scenarios'),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 800,
                    maxHeight: 300,
                  ),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 300 / 200,
                        ),
                    shrinkWrap: true,
                    itemCount: _scenarios.length,
                    itemBuilder: (context, index) {
                      final scenario = _scenarios[index];
                      final filled = _scenarioIndex == index;
                      Widget child = Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [Flexible(child: Text(scenario.$1))],
                        ),
                      );
                      if (filled) {
                        child = Card.filled(child: child);
                      } else {
                        child = Card.outlined(child: child);
                      }
                      return GestureDetector(
                        onTap: () => _switchToScenario(index),
                        child: child,
                      );
                    },
                  ),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150, maxWidth: 450),
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        TextFormField(
                          controller: _controller,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: ColorScheme.of(context).onSecondary,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: ColorScheme.of(context).onSecondary,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            hintText: 'Ask',
                            suffix: const SizedBox(width: 24),
                          ),
                          onFieldSubmitted: (value) {
                            _onReply();
                          },
                        ),
                        Positioned(
                          right: 6,
                          bottom: 4,
                          child: ValueListenableBuilder(
                            valueListenable: _controller,
                            builder: (context, value, child) {
                              return IconButton.outlined(
                                icon: const Icon(Icons.arrow_upward_rounded),
                                onPressed: _controller.text.isEmpty
                                    ? null
                                    : _onReply,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 24,
                      maxWidth: 24,
                      minHeight: 24,
                      minWidth: 24,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _isRunning
                            ? const CircularProgressIndicator.adaptive()
                            : const SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
