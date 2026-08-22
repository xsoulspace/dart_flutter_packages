import 'dart:async';

import 'package:flutter/material.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

/// A selectable scenario in the example UI: the scenario plus its label.
typedef ScenarioRecord = ({Scenario scenario, String title});

void main() {
  // debugProfilePlatformChannels = true;
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
        colorScheme: .fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        ),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// Which inference backend a scenario uses.
enum ScenarioBackend {
  /// On-device Apple Foundation Models (macOS 26+).
  apple,

  /// Hosted OpenRouter API (requires an API key).
  openRouter,
}

/// A scenario drives a fresh ecsly [World] through the actor schedules.
///
/// Each scenario builds its own world (so switching scenarios is isolated),
/// registers the Apple Foundation model + tools, spawns a scene + actor with
/// an [OpenDecision], and runs the [HarnessLoop] until the response lands as
/// an indexed beat in the narrative graph.
sealed class Scenario {
  bool isInitialized = false;
  World? world;
  Entity? actor;

  /// Loop for the current run — kept so [dispose] can stop a run in flight.
  HarnessLoop? _loop;

  /// Build the world, register resources/handlers, and spawn the actor.
  ///
  /// Subclasses override [setupWorld] to add model bindings and tools, and
  /// [spawnActor] to configure the actor's system prompt / decision.
  ///
  /// [backend] selects which inference backend routes the actor's generation:
  /// [ScenarioBackend.apple] (on-device Apple Foundation) or
  /// [ScenarioBackend.openRouter] (hosted OpenRouter API).
  Future<String> init({
    required String text,
    ScenarioBackend backend = ScenarioBackend.apple,
    String openRouterApiKey = '',
  }) async {
    isInitialized = true;
    final world = World()..addPlugin(AgentPlugin());

    // Register both backends as first-class models in the router, so an actor
    // can swap inference at runtime by changing its [ActorModel]. Apple
    // Foundation is on-device; OpenRouter is a hosted API (requires a key).
    final router = ModelRouter(
      inferenceClientsBuilders: {
        DefaultModelNames.appleFoundation: () => AppleFoundationInferenceClient(
          api: AppleFoundationInferenceClient.initApi(),
        ),
        OpenRouterModelNames.openRouter: () =>
            OpenRouterInferenceClient(apiKey: openRouterApiKey),
      },
    );

    // Bind stable model ids so the actor can reference them via [ActorModel].
    // Tier 1 = stronger (OpenRouter) — escalation moves up tiers.
    final appleModelId = ModelId('apple-foundation');
    final openRouterModelId = ModelId('model-openrouter');
    router.models[appleModelId] = const Model(
      id: ModelId('apple-foundation'),
      name: DefaultModelNames.appleFoundation,
      tier: 0,
    );
    router.models[openRouterModelId] = const Model(
      id: ModelId('model-openrouter'),
      name: OpenRouterModelNames.openRouter,
      tier: 1,
    );

    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..flush();

    // Route generation through the default handler, which resolves the model
    // from the router by the actor's [ActorModel.modelId].
    final handler = DefaultGenerationHandler()..router = router;
    world.getResource<GenerationHandlerResource>().registerDefault(handler);

    setupWorld(world);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    actor = spawnActor(
      world,
      scene,
      text,
      modelId: backend == ScenarioBackend.openRouter
          ? openRouterModelId
          : appleModelId,
    );

    world.flush();
    this.world = world;
    return '';
  }

  /// Hook for subclasses to register tools / extra resources.
  void setupWorld(World world) {}

  /// Spawn the actor with an [OpenDecision] derived from [text].
  ///
  /// [modelId] selects which registered model the actor uses — swapping this
  /// component at runtime swaps the inference backend.
  Entity spawnActor(
    World world,
    Entity scene,
    String text, {
    ModelId modelId = ModelId.empty,
  }) {
    final actorId = AgentId.create();
    final actor = world.spawnComponents([
      Actor(agentId: actorId),
      ActorModel(modelId: modelId),
      PresentInScene(sceneEntity: scene),
      OpenDecision(prompt: text),
    ]);
    return actor;
  }

  /// Run the schedules until the world goes idle, then return the latest
  /// model-response [TextContent] (or '' if none arrived).
  ///
  /// Response beats are indexed into the [FacetIndex]; we scan the world's
  /// complete text beats for the most recent one.
  Future<String> run() async {
    final world = this.world;
    if (world == null) return '';

    // Drive all schedules until no decisions / responses / tasks remain.
    final loop = HarnessLoop(world: world);
    _loop = loop;
    await loop.runUntilIdle();
    _loop = null;

    // Latest complete text beat = the model's most recent response.
    String? last;
    for (final (_, _, content) in world.query2<BeatModality, TextContent>()) {
      if (content.text.isNotEmpty) last = content.text;
    }
    return last ?? '';
  }

  void dispose() {
    isInitialized = false;
    // Stop any running loop before clearing the world, so it doesn't tick a
    // cleared world (which would crash on a missing schedule).
    _loop?.stop();
    _loop = null;
    world?.clear();
    world = null;
    actor = null;
  }
}

/// Human -> Agent (one-shot)
class ScenarioV1SendMessageGetAnswer extends Scenario {
  @override
  Future<String> init({
    required String text,
    ScenarioBackend backend = ScenarioBackend.apple,
    String openRouterApiKey = '',
  }) async {
    await super.init(
      text: text,
      backend: backend,
      openRouterApiKey: openRouterApiKey,
    );
    return run();
  }
}

/// Human -> Agent -> Human -> Agent -> Human
///
/// Keeps the same world/actor across turns by re-inserting an [OpenDecision]
/// on each reply, so beats accumulate in the narrative graph.
class ScenarioV2KeepPrimitiveMemory extends Scenario {
  @override
  Future<String> init({
    required String text,
    ScenarioBackend backend = ScenarioBackend.apple,
    String openRouterApiKey = '',
  }) async {
    await super.init(
      text: text,
      backend: backend,
      openRouterApiKey: openRouterApiKey,
    );
    return run();
  }

  Future<String> reply(String text) async {
    final world = this.world;
    final actor = this.actor;
    if (world == null || actor == null) return '';
    world.upsertComponent(actor, OpenDecision(prompt: text));
    world.flush();
    return run();
  }
}

/// Schema + function call for weather
class ScenarioV3FunctionCallAndSchema extends Scenario {
  SchemaBundle get _characterGenOutputSchema {
    final npcSchema = FM.object(
      'Npc',
      description: 'A character that can order coffee',
      properties: () => [
        FM.prop('name', description: 'First name, Second Name', FM.string()),
        FM.prop('level', FM.double(guides: [RangeGuide(1, 10)])),
        FM.prop('attributes', FM.array(FM.ref('Attribute'), min: 1, max: 2)),
        FM.prop('encounter', FM.ref('Encounter')),
      ],
    );

    final attributeSchema = FM.enum_('Attribute', ['bold', 'tired', 'hungry']);

    final encounterSchema = FM.anyOf('Encounter', [
      FM.object(
        'OrderCoffee',
        properties: () => [FM.prop('drink', FM.string())],
      ),
      FM.object(
        'WantToTalkToManager',
        properties: () => [FM.prop('complaint', FM.string())],
      ),
    ]);

    // Root + dependencies
    final schema = SchemaBundle(
      root: npcSchema,
      dependencies: [attributeSchema, encounterSchema],
    );
    return schema;
  }

  @override
  void setupWorld(World world) {
    // TODO(arenukvern): restore character generation
    final registry = ToolRegistry();
    registry.register(
      ToolDef.encode(
        name: ToolName('getWeatherForHour'),
        description: 'Returns weather for a specific hour of today',
        argsSchema: SchemaBundle(
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
            _ => (16, "sunny"),
          };
          return {'hour': hour, 'temp': temp, 'condition': condition};
        },
      ),
    );
    world.getResource<ToolRegistryResource>().register('default', registry);
  }

  @override
  Entity spawnActor(
    World world,
    Entity scene,
    String text, {
    ModelId modelId = ModelId.empty,
  }) {
    final actor = super.spawnActor(world, scene, text, modelId: modelId);
    world.upsertComponent(actor, const ActorTools(registryName: 'default'));
    // Give the decision a structured output schema.
    world.upsertComponent(
      actor,
      OpenDecision(
        prompt: text,
        schema: SchemaBundle(
          root: FM.object(
            'weather',
            properties: () => [FM.prop('condition', FM.double())],
          ),
        ),
      ),
    );
    return actor;
  }

  @override
  Future<String> init({
    required String text,
    ScenarioBackend backend = ScenarioBackend.apple,
    String openRouterApiKey = '',
  }) async {
    await super.init(
      text: text,
      backend: backend,
      openRouterApiKey: openRouterApiKey,
    );
    return run();
  }

  Future<String> reply(String text) async {
    final world = this.world;
    final actor = this.actor;
    if (world == null || actor == null) return '';
    world.upsertComponent(
      actor,
      OpenDecision(prompt: text, schema: _characterGenOutputSchema),
    );
    world.flush();
    return run();
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final _scenarioV1 = ScenarioV1SendMessageGetAnswer();
  final _scenarioV2 = ScenarioV2KeepPrimitiveMemory();
  final _scenarioV3 = ScenarioV3FunctionCallAndSchema();
  final _messages = ImmutableOrderedList<String>();

  final TextEditingController _controller = TextEditingController();

  String get _txt => _controller.text;

  bool _isRunning = false;
  int _scenarioIndex = 0;
  ScenarioBackend _backend = ScenarioBackend.apple;
  final TextEditingController _apiKeyController = TextEditingController();

  List<ScenarioRecord> get _scenarios => [
    (scenario: _scenarioV1, title: 'one-text'),
    (scenario: _scenarioV2, title: 'h -> llm -> h -> llm'),
    (scenario: _scenarioV3, title: 'scheme + tool call: Weather / Character'),
  ];

  T _getScenarioByIndex<T extends Scenario>() =>
      _scenarios[_scenarioIndex].scenario as T;
  void _switchToScenario(int? index) {
    final i = index;
    if (i == null || _scenarioIndex == i) return;
    _cleanup();
    setState(() => _scenarioIndex = i);
  }

  void _cleanup() {
    _messages.clear();
    for (var scenario in _scenarios) {
      scenario.scenario.dispose();
    }
  }

  void _setLoading() => setState(() {
    _isRunning = true;
  });

  Future<void> _initScenario() async {
    final scenario = _getScenarioByIndex();
    _setLoading();
    final r = await scenario.init(
      text: _txt,
      backend: _backend,
      openRouterApiKey: _apiKeyController.text.trim(),
    );
    setState(() {
      _messages
        ..add(_txt)
        ..add(r);
      _controller.clear();
      _isRunning = false;
    });
  }

  Future<void> _scenarioReply() async {
    _setLoading();

    final scenario = _getScenarioByIndex();
    final r = switch (scenario) {
      ScenarioV2KeepPrimitiveMemory() => await scenario.reply(_txt),
      ScenarioV3FunctionCallAndSchema() => await scenario.reply(_txt),
      _ => '',
    };
    setState(() {
      _messages
        ..add(_txt)
        ..add(r);
      _controller.clear();
      _isRunning = false;
    });
  }

  void _onReply() {
    final scenario = _getScenarioByIndex();
    switch (scenario) {
      case final ScenarioV1SendMessageGetAnswer _:
        _cleanup();
        _initScenario();

      case final ScenarioV2KeepPrimitiveMemory i:
        if (i.isInitialized) {
          _scenarioReply();
        } else {
          _cleanup();
          _initScenario();
        }
      case final ScenarioV3FunctionCallAndSchema i:
        if (i.isInitialized) {
          _scenarioReply();
        } else {
          _cleanup();
          _initScenario();
        }
    }
  }

  @override
  void dispose() {
    _cleanup();
    _controller.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: .end,
          crossAxisAlignment: .center,
          spacing: 4,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 450),
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
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text('scenarios'),
                Container(
                  constraints: BoxConstraints(maxWidth: 800, maxHeight: 300),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                          crossAxisAlignment: .start,
                          mainAxisSize: .min,
                          children: [Flexible(child: Text(scenario.title))],
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
              constraints: BoxConstraints(maxWidth: 450),
              child: Column(
                crossAxisAlignment: .start,
                mainAxisSize: .min,
                children: [
                  Text('backend'),
                  SegmentedButton<ScenarioBackend>(
                    segments: const [
                      ButtonSegment(
                        value: ScenarioBackend.apple,
                        label: Text('Apple Foundation'),
                      ),
                      ButtonSegment(
                        value: ScenarioBackend.openRouter,
                        label: Text('OpenRouter'),
                      ),
                    ],
                    selected: {_backend},
                    onSelectionChanged: (selection) {
                      setState(() => _backend = selection.first);
                    },
                  ),
                  if (_backend == ScenarioBackend.openRouter)
                    TextFormField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'OpenRouter API key',
                        hintText: 'sk-or-...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 450, maxHeight: 150),
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
                            suffix: SizedBox(width: 24),
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
                                icon: Icon(Icons.arrow_upward_rounded),
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
                    constraints: BoxConstraints(
                      maxHeight: 24,
                      maxWidth: 24,
                      minHeight: 24,
                      minWidth: 24,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: .new(milliseconds: 250),

                        child: _isRunning
                            ? CircularProgressIndicator.adaptive()
                            : SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
